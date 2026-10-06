#include "firebase_firestore_native.h"

#include <cstdint>
#include <limits>
#include <unordered_set>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>

#include "../core/firebase_app_native.h"
#include "value_convert.h"

using firebase::Future;
using firebase::firestore::DocumentReference;
using firebase::firestore::DocumentSnapshot;
using firebase::firestore::FieldValue;
using firebase::firestore::MapFieldValue;
using firebase::firestore::Query;
using firebase::firestore::QuerySnapshot;
using firebase::firestore::SetOptions;
using firebase::firestore::Source;
using firebase::firestore::MetadataChanges;
using firebase::firestore::WriteBatch;
using godot::Array;
using godot::D_METHOD;
using godot::Dictionary;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

Outcome invalid(const String &p_reason) {
	return Outcome::failure(kInvalidArgument, p_reason);
}

bool is_string(const Variant &p_value) {
	return p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME;
}

// Validate query shapes/combinations before any SDK builder can throw/abort. The pinned
// iOS query_core ConflictingOps permits multiple inequality and "in" fields.
String validate_query(const Array &p_filters, const Array &p_order_by, int64_t p_limit) {
	bool not_equal_seen = false;
	for (int64_t i = 0; i < p_filters.size(); ++i) {
		if (p_filters[i].get_type() != Variant::ARRAY) {
			return "filter must be [field path, op, value]";
		}
		const Array filter = p_filters[i];
		if (filter.size() != 3 || !is_field_path(filter[0]) || !is_string(filter[1])) {
			return "filter must be [field path, op, value]";
		}
		const String op = filter[1];
		if (op != "==" && op != "!=" && op != "<" && op != "<=" && op != ">" && op != ">=" && op != "in" && op != "array-contains") {
			return "unknown filter operator " + op;
		}
		if (op == "!=") {
			if (not_equal_seen) {
				return "a query supports only one != filter";
			}
			not_equal_seen = true;
		}
		Array values;
		if (op == "in") {
			if (filter[2].get_type() != Variant::ARRAY) {
				return "'in' needs an array with 1-30 values";
			}
			values = filter[2];
			if (values.is_empty() || values.size() > 30) {
				return "'in' needs an array with 1-30 values";
			}
		} else {
			values.push_back(filter[2]);
		}
		const bool document_id = String(filter[0]) == "__name__";
		if (document_id && op == "array-contains") {
			return "document IDs cannot use array-contains";
		}
		for (int64_t j = 0; j < values.size(); ++j) {
			if (document_id && (!is_string(values[j]) || String(values[j]).is_empty() || String(values[j]).contains("/"))) {
				return "document ID must be a non-empty string without '/'";
			}
		}
	}
	for (int64_t i = 0; i < p_order_by.size(); ++i) {
		if (p_order_by[i].get_type() != Variant::ARRAY) {
			return "order must be [field path, asc | desc]";
		}
		const Array order = p_order_by[i];
		if (order.size() != 2 || !is_field_path(order[0]) || !is_string(order[1]) || (String(order[1]) != "asc" && String(order[1]) != "desc")) {
			return "order must be [field path, asc | desc]";
		}
	}
	return p_limit > std::numeric_limits<int32_t>::max() ? String("limit must be at most 2147483647") : String();
}

bool parse_source(const String &p_source, Source &r_source) {
	if (p_source == "default") {
		r_source = Source::kDefault;
	} else if (p_source == "cache") {
		r_source = Source::kCache;
	} else if (p_source == "server") {
		r_source = Source::kServer;
	} else {
		return false;
	}
	return true;
}

String add_filter(const Array &p_filter, Query &r_query) {
	if (p_filter.size() != 3 || !is_field_path(p_filter[0])) {
		return "filter must be [field path, op, value]";
	}
	const std::string field = to_std(p_filter[0]);
	const String op = p_filter[1];
	if (op == "in") {
		const Array items = p_filter[2];
		std::vector<FieldValue> values;
		values.reserve(static_cast<size_t>(items.size()));
		for (int64_t i = 0; i < items.size(); i++) {
			FieldValue value;
			const String reason = to_query_value(items[i], value);
			if (!reason.is_empty()) {
				return reason;
			}
			values.push_back(value);
		}
		if (values.empty() || values.size() > 30) {
			return "'in' needs an array with 1-30 values";
		}
		r_query = r_query.WhereIn(field, values);
		return String();
	}
	FieldValue value;
	const String reason = to_query_value(p_filter[2], value);
	if (!reason.is_empty()) {
		return reason;
	}
	if (op == "==") {
		r_query = r_query.WhereEqualTo(field, value);
	} else if (op == "!=") {
		r_query = r_query.WhereNotEqualTo(field, value);
	} else if (op == "<") {
		r_query = r_query.WhereLessThan(field, value);
	} else if (op == "<=") {
		r_query = r_query.WhereLessThanOrEqualTo(field, value);
	} else if (op == ">") {
		r_query = r_query.WhereGreaterThan(field, value);
	} else if (op == ">=") {
		r_query = r_query.WhereGreaterThanOrEqualTo(field, value);
	} else if (op == "array-contains") {
		r_query = r_query.WhereArrayContains(field, value);
	} else {
		return "unknown filter operator " + op;
	}
	return String();
}

String build_query(Query &r_query, const Array &p_filters, const Array &p_order_by, int64_t p_limit) {
	const String validation = validate_query(p_filters, p_order_by, p_limit);
	if (!validation.is_empty()) {
		return validation;
	}
	for (int64_t i = 0; i < p_filters.size(); i++) {
		const String reason = add_filter(p_filters[i], r_query);
		if (!reason.is_empty()) {
			return reason;
		}
	}
	for (int64_t i = 0; i < p_order_by.size(); i++) {
		const Array order = p_order_by[i];
		if (order.size() != 2 || !is_field_path(order[0]) || (String(order[1]) != "asc" && String(order[1]) != "desc")) {
			return "order must be [field path, \"asc\" | \"desc\"]";
		}
		const bool descending = String(order[1]) == "desc";
		r_query = r_query.OrderBy(to_std(order[0]), descending ? Query::Direction::kDescending : Query::Direction::kAscending);
	}
	if (p_limit > std::numeric_limits<int32_t>::max()) {
		return "limit must be at most 2147483647";
	}
	if (p_limit > 0) {
		r_query = r_query.Limit(static_cast<int32_t>(p_limit));
	}
	return String();
}

String add_batch_op(firebase::firestore::Firestore *p_db, const Variant &p_op, WriteBatch &r_batch) {
	if (p_op.get_type() != Variant::DICTIONARY) {
		return "batch op must be a dictionary";
	}
	const Dictionary op = p_op;
	const Variant path = op.get("path", Variant());
	if (!is_string(path) || !is_document_path(path)) {
		return "batch op needs a document path";
	}
	const Variant kind = op.get("op", Variant());
	if (!is_string(kind) || (String(kind) != "set" && String(kind) != "update" && String(kind) != "delete")) {
		return "unknown batch op";
	}
	const DocumentReference document = p_db->Document(to_std(path));
	if (String(kind) == "delete") {
		r_batch.Delete(document);
		return String();
	}
	const Variant data = op.get("data", Variant());
	if (data.get_type() != Variant::DICTIONARY) {
		return "batch " + String(kind) + " needs data";
	}
	MapFieldValue fields;
	if (String(kind) == "update") {
		const String reason = to_update_field_value(data, fields);
		if (!reason.is_empty()) {
			return reason;
		}
		r_batch.Update(document, fields);
		return String();
	}
	const Variant merge = op.get("merge", false);
	if (merge.get_type() != Variant::BOOL) {
		return "batch merge must be a bool";
	}
	const String reason = to_map_field_value(data, merge, fields);
	if (!reason.is_empty()) {
		return reason;
	}
	r_batch.Set(document, fields, bool(merge) ? SetOptions::Merge() : SetOptions());
	return String();
}

} // namespace

namespace {
std::unordered_set<FirebaseFirestoreNative *> active_modules;
}

FirebaseFirestoreNative::FirebaseFirestoreNative() {
	active_modules.insert(this);
}

FirebaseFirestoreNative::~FirebaseFirestoreNative() {
	remove_all_listeners();
	active_modules.erase(this);
}

void FirebaseFirestoreNative::shutdown_all() {
	// Listener registrations and the Firestore instance belong to the App.
	for (FirebaseFirestoreNative *module : active_modules) {
		module->remove_all_listeners();
		module->db = nullptr;
	}
}

void FirebaseFirestoreNative::remove_all_listeners() {
	for (auto &listener : listeners) {
		listener.second.Remove();
	}
	listeners.clear();
}

godot::Error FirebaseFirestoreNative::initialize() {
	if (db) {
		return godot::ERR_ALREADY_IN_USE;
	}
	firebase::App *app = FirebaseAppNative::get_app();
	if (app == nullptr) {
		return godot::ERR_UNCONFIGURED;
	}
	firebase::InitResult result = firebase::kInitResultSuccess;
	db = firebase::firestore::Firestore::GetInstance(app, &result);
	if (db == nullptr || result != firebase::kInitResultSuccess) {
		db = nullptr;
		return godot::ERR_CANT_CREATE;
	}
	return godot::OK;
}

int64_t FirebaseFirestoreNative::start_with_document(const String &p_path, const std::function<void(DocumentReference, Completion)> &p_request) {
	return start([this, &p_path, &p_request](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
		} else if (!is_document_path(p_path)) {
			done(invalid("not a document path: " + p_path));
		} else {
			p_request(db->Document(to_std(p_path)), std::move(done));
		}
	});
}

int64_t FirebaseFirestoreNative::get_doc(const String &p_path, const String &p_source) {
	return start_with_document(p_path, [&p_source](DocumentReference document, Completion done) {
		Source source;
		if (!parse_source(p_source, source)) {
			done(invalid("source must be default, cache, or server"));
			return;
		}
		complete_when_done(document.Get(source), std::move(done), [](const Future<DocumentSnapshot> &future) {
			return Variant(to_snapshot(*future.result()));
		});
	});
}

int64_t FirebaseFirestoreNative::set_doc(const String &p_path, const Dictionary &p_data, bool p_merge) {
	return start_with_document(p_path, [&p_data, p_merge](DocumentReference document, Completion done) {
		MapFieldValue fields;
		const String reason = to_map_field_value(p_data, p_merge, fields);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(document.Set(fields, p_merge ? SetOptions::Merge() : SetOptions()), std::move(done));
	});
}

int64_t FirebaseFirestoreNative::update_doc(const String &p_path, const Dictionary &p_data) {
	return start_with_document(p_path, [&p_data](DocumentReference document, Completion done) {
		MapFieldValue fields;
		const String reason = to_update_field_value(p_data, fields);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(document.Update(fields), std::move(done));
	});
}

int64_t FirebaseFirestoreNative::delete_doc(const String &p_path) {
	return start_with_document(p_path, [](DocumentReference document, Completion done) {
		complete_when_done(document.Delete(), std::move(done));
	});
}

int64_t FirebaseFirestoreNative::run_query(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const String &p_source) {
	return start_query(p_collection, p_filters, p_order_by, p_limit, p_source, false);
}

int64_t FirebaseFirestoreNative::run_query_snapshot(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const String &p_source) {
	return start_query(p_collection, p_filters, p_order_by, p_limit, p_source, true);
}

int64_t FirebaseFirestoreNative::set_network_enabled(bool p_enabled) {
	return start([this, p_enabled](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
			return;
		}
		complete_when_done(p_enabled ? db->EnableNetwork() : db->DisableNetwork(), std::move(done));
	});
}

int64_t FirebaseFirestoreNative::wait_pending_writes() {
	return start([this](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
			return;
		}
		// Firebase owns the persisted queue, current-user scope and cancellation.
		complete_when_done(db->WaitForPendingWrites(), std::move(done));
	});
}

int64_t FirebaseFirestoreNative::start_query(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const String &p_source, bool p_with_metadata) {
	return start([&](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
			return;
		}
		if (!is_collection_path(p_collection)) {
			done(invalid("not a collection path: " + p_collection));
			return;
		}
		Source source;
		if (!parse_source(p_source, source)) {
			done(invalid("source must be default, cache, or server"));
			return;
		}
		Query query = db->Collection(to_std(p_collection));
		const String reason = build_query(query, p_filters, p_order_by, p_limit);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(query.Get(source), std::move(done), [p_with_metadata](const Future<QuerySnapshot> &future) {
			Array snapshots;
			for (const DocumentSnapshot &snapshot : future.result()->documents()) {
				snapshots.push_back(to_snapshot(snapshot));
			}
			if (p_with_metadata) {
				Dictionary result;
				result["documents"] = snapshots;
				result["metadata"] = to_metadata(future.result()->metadata());
				return Variant(result);
			}
			return Variant(snapshots);
		});
	});
}

int64_t FirebaseFirestoreNative::commit_batch(const Array &p_ops) {
	return start([&](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
			return;
		}
		WriteBatch batch = db->batch();
		for (int64_t i = 0; i < p_ops.size(); i++) {
			const String reason = add_batch_op(db, p_ops[i], batch);
			if (!reason.is_empty()) {
				done(invalid(reason));
				return;
			}
		}
		complete_when_done(batch.Commit(), std::move(done));
	});
}

int64_t FirebaseFirestoreNative::listen_doc(const String &p_path, bool p_include_metadata_changes) {
	if (db == nullptr || !is_document_path(p_path)) {
		return 0;
	}
	const int64_t id = ++next_listener_id;
	const uint64_t object_id = get_instance_id();
	listeners[id] = db->Document(to_std(p_path)).AddSnapshotListener(
			p_include_metadata_changes ? MetadataChanges::kInclude : MetadataChanges::kExclude,
			[object_id, id](const DocumentSnapshot &snapshot, firebase::firestore::Error error, const std::string &message) {
				const bool ok = error == firebase::firestore::kErrorOk;
				const Array args = Array::make(id, ok, ok ? to_snapshot(snapshot) : Dictionary(), static_cast<int>(error), to_godot(message));
				emit_deferred_to(object_id, "document_changed", args);
			});
	return id;
}

void FirebaseFirestoreNative::remove_listener(int64_t p_id) {
	auto listener = listeners.find(p_id);
	if (listener != listeners.end()) {
		listener->second.Remove();
		listeners.erase(listener);
	}
}

void FirebaseFirestoreNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseFirestoreNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("get_doc", "path", "source"), &FirebaseFirestoreNative::get_doc, DEFVAL("default"));
	godot::ClassDB::bind_method(D_METHOD("set_doc", "path", "data", "merge"), &FirebaseFirestoreNative::set_doc);
	godot::ClassDB::bind_method(D_METHOD("update_doc", "path", "data"), &FirebaseFirestoreNative::update_doc);
	godot::ClassDB::bind_method(D_METHOD("delete_doc", "path"), &FirebaseFirestoreNative::delete_doc);
	godot::ClassDB::bind_method(D_METHOD("run_query", "collection_path", "filters", "order_by", "limit", "source"), &FirebaseFirestoreNative::run_query, DEFVAL("default"));
	godot::ClassDB::bind_method(D_METHOD("run_query_snapshot", "collection_path", "filters", "order_by", "limit", "source"), &FirebaseFirestoreNative::run_query_snapshot, DEFVAL("default"));
	godot::ClassDB::bind_method(D_METHOD("set_network_enabled", "enabled"), &FirebaseFirestoreNative::set_network_enabled);
	godot::ClassDB::bind_method(D_METHOD("wait_pending_writes"), &FirebaseFirestoreNative::wait_pending_writes);
	godot::ClassDB::bind_method(D_METHOD("commit_batch", "ops"), &FirebaseFirestoreNative::commit_batch);
	godot::ClassDB::bind_method(D_METHOD("listen_doc", "path", "include_metadata_changes"), &FirebaseFirestoreNative::listen_doc, DEFVAL(false));
	godot::ClassDB::bind_method(D_METHOD("remove_listener", "id"), &FirebaseFirestoreNative::remove_listener);
	ADD_SIGNAL(godot::MethodInfo("document_changed",
			godot::PropertyInfo(Variant::INT, "listener_id"), godot::PropertyInfo(Variant::BOOL, "ok"),
			godot::PropertyInfo(Variant::DICTIONARY, "snapshot"), godot::PropertyInfo(Variant::INT, "error_code"),
			godot::PropertyInfo(Variant::STRING, "error_message")));
}

} // namespace godot_firebase
