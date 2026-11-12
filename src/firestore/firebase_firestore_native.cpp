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
using firebase::firestore::AggregateQuerySnapshot;
using firebase::firestore::AggregateSource;
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

// Cursor keys of FirebaseFirestore.CURSOR_KEYS, in the order build_query() applies them.
const char *const kCursorKeys[] = { "start_at", "start_after", "end_at", "end_before" };

bool is_list_op(const String &p_op) {
	return p_op == "in" || p_op == "not-in" || p_op == "array-contains-any";
}

bool is_document_id(const Variant &p_id) {
	return is_string(p_id) && !String(p_id).is_empty() && !String(p_id).contains("/");
}

// Same rules as FirebaseFirestore._validate_filters(); query_core ConflictingOps() permits
// several inequality, "in" and "array-contains-any" filters. The array-contains rules are the server's.
String validate_filters(const Array &p_filters) {
	int not_equal = 0;
	int not_in = 0;
	int array_contains = 0;
	bool array_contains_any = false;
	bool disjunctive = false;
	for (int64_t i = 0; i < p_filters.size(); ++i) {
		if (p_filters[i].get_type() != Variant::ARRAY) {
			return "filter must be [field path, op, value]";
		}
		const Array filter = p_filters[i];
		if (filter.size() != 3 || !is_field_path(filter[0]) || !is_string(filter[1])) {
			return "filter must be [field path, op, value]";
		}
		const String op = filter[1];
		if (op != "==" && op != "!=" && op != "<" && op != "<=" && op != ">" && op != ">=" && op != "array-contains" && !is_list_op(op)) {
			return "unknown filter operator " + op;
		}
		not_equal += op == "!=" ? 1 : 0;
		not_in += op == "not-in" ? 1 : 0;
		array_contains += op == "array-contains" ? 1 : 0;
		array_contains_any = array_contains_any || op == "array-contains-any";
		disjunctive = disjunctive || op == "in" || array_contains_any;
		Array values;
		if (is_list_op(op)) {
			const int64_t max_values = op == "not-in" ? 10 : 30;
			if (filter[2].get_type() != Variant::ARRAY || Array(filter[2]).is_empty() || Array(filter[2]).size() > max_values) {
				return op + String(" needs an array with 1-") + String::num_int64(max_values) + String(" values");
			}
			values = filter[2];
		} else {
			values.push_back(filter[2]);
		}
		const bool document_id = String(filter[0]) == "__name__";
		if (document_id && op.begins_with("array-contains")) {
			return "document IDs cannot use " + op;
		}
		for (int64_t j = 0; j < values.size(); ++j) {
			if (document_id && !is_document_id(values[j])) {
				return "document ID must be a non-empty string without '/'";
			}
		}
	}
	if (not_equal > 1 || not_in > 1) {
		return "a query supports only one != and one not-in filter";
	}
	if (not_in > 0 && (not_equal > 0 || disjunctive)) {
		return "not-in cannot be combined with !=, in or array-contains-any";
	}
	if (array_contains > 1 || (array_contains > 0 && array_contains_any)) {
		return "a query supports only one array-contains filter, not combined with array-contains-any";
	}
	return String();
}

// Same rules as FirebaseFirestore._validate_cursor(); value conversion is checked by build_query().
String validate_cursor(const Dictionary &p_cursor, const Array &p_order_by) {
	if ((p_cursor.has("start_at") && p_cursor.has("start_after")) || (p_cursor.has("end_at") && p_cursor.has("end_before"))) {
		return "a cursor has at most one start and one end";
	}
	const Array keys = p_cursor.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const Variant key = keys[i];
		const bool known = is_string(key) && (String(key) == kCursorKeys[0] || String(key) == kCursorKeys[1] || String(key) == kCursorKeys[2] || String(key) == kCursorKeys[3]);
		if (!known) {
			return "unknown cursor key";
		}
		// The SDKs abort on more values than explicit orders, or a bad document ID for __name__.
		const Variant values = p_cursor[key];
		if (values.get_type() != Variant::ARRAY || Array(values).is_empty() || Array(values).size() > p_order_by.size()) {
			return String(key) + " needs a value for each leading order_by field";
		}
		for (int64_t j = 0; j < Array(values).size(); ++j) {
			if (String(Array(p_order_by[j])[0]) == "__name__" && !is_document_id(Array(values)[j])) {
				return "document ID must be a non-empty string without '/'";
			}
		}
	}
	return String();
}

// Validate query shapes/combinations before any SDK builder can throw/abort.
String validate_query(const Array &p_filters, const Array &p_order_by, int64_t p_limit, const Dictionary &p_cursor) {
	const String reason = validate_filters(p_filters);
	if (!reason.is_empty()) {
		return reason;
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
	if (p_limit > std::numeric_limits<int32_t>::max()) {
		return "limit must be at most 2147483647";
	}
	return validate_cursor(p_cursor, p_order_by);
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

// Only build_query() calls this, after validate_query(): just the value conversion can fail here.
String add_filter(const Array &p_filter, Query &r_query) {
	const std::string field = to_std(p_filter[0]);
	const String op = p_filter[1];
	if (is_list_op(op)) {
		std::vector<FieldValue> values;
		const String reason = to_query_values(r_query.firestore(), p_filter[2], values);
		if (!reason.is_empty()) {
			return reason;
		}
		r_query = op == "in" ? r_query.WhereIn(field, values) : op == "not-in" ? r_query.WhereNotIn(field, values) : r_query.WhereArrayContainsAny(field, values);
		return String();
	}
	FieldValue value;
	const String reason = to_query_value(r_query.firestore(), p_filter[2], value);
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
	} else { // array-contains
		r_query = r_query.WhereArrayContains(field, value);
	}
	return String();
}

// Cursors come after the orders: the SDK aborts on OrderBy() after StartAt() or EndAt().
String add_cursor(const Dictionary &p_cursor, Query &r_query) {
	for (const char *key : kCursorKeys) {
		if (!p_cursor.has(key)) {
			continue;
		}
		const Array items = p_cursor[key];
		std::vector<FieldValue> values;
		values.reserve(static_cast<size_t>(items.size()));
		for (int64_t i = 0; i < items.size(); i++) {
			FieldValue value;
			const String reason = to_query_value(r_query.firestore(), items[i], value);
			if (!reason.is_empty()) {
				return String(key) + ": " + reason;
			}
			values.push_back(value);
		}
		const String name = key;
		r_query = name == "start_at" ? r_query.StartAt(values) : name == "start_after" ? r_query.StartAfter(values) : name == "end_at" ? r_query.EndAt(values) : r_query.EndBefore(values);
	}
	return String();
}

String build_query(Query &r_query, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const Dictionary &p_cursor) {
	const String validation = validate_query(p_filters, p_order_by, p_limit, p_cursor);
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
		const bool descending = String(order[1]) == "desc";
		r_query = r_query.OrderBy(to_std(order[0]), descending ? Query::Direction::kDescending : Query::Direction::kAscending);
	}
	if (p_limit > 0) {
		r_query = r_query.Limit(static_cast<int32_t>(p_limit));
	}
	return add_cursor(p_cursor, r_query);
}

// Builds the query, or returns why it is invalid; `p_db` must be initialized.
String to_query(firebase::firestore::Firestore *p_db, const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const Dictionary &p_cursor, Query &r_query) {
	if (!is_collection_path(p_collection)) {
		return "not a collection path: " + p_collection;
	}
	r_query = p_db->Collection(to_std(p_collection));
	return build_query(r_query, p_filters, p_order_by, p_limit, p_cursor);
}

// {documents, metadata}
Dictionary to_query_snapshot(const QuerySnapshot &p_snapshot) {
	Array documents;
	for (const DocumentSnapshot &document : p_snapshot.documents()) {
		documents.push_back(to_snapshot(document));
	}
	Dictionary result;
	result["documents"] = documents;
	result["metadata"] = to_metadata(p_snapshot.metadata());
	return result;
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
		const String reason = to_update_field_value(p_db, data, fields);
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
	const String reason = to_map_field_value(p_db, data, merge, fields);
	if (!reason.is_empty()) {
		return reason;
	}
	r_batch.Set(document, fields, bool(merge) ? SetOptions::Merge() : SetOptions());
	return String();
}

} // namespace

namespace {
std::unordered_set<FirebaseFirestoreNative *> active_modules;
// Every wrapper shares one Firestore, whose settings the SDK accepts only before
// its first use; changing them later stops the process.
firebase::firestore::Firestore *configured_firestore = nullptr;
std::string configured_emulator;
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
	configured_firestore = nullptr;
	configured_emulator.clear();
}

void FirebaseFirestoreNative::remove_all_listeners() {
	for (auto &listener : listeners) {
		listener.second.Remove();
	}
	listeners.clear();
}

godot::Error FirebaseFirestoreNative::initialize(const String &p_emulator_host) {
	if (db) {
		return godot::ERR_ALREADY_IN_USE;
	}
	std::string emulator_host;
	int emulator_port = 0;
	if (!parse_emulator_host(p_emulator_host, emulator_host, emulator_port)) {
		return godot::ERR_INVALID_PARAMETER;
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
	const std::string emulator = to_std(p_emulator_host);
	if (configured_firestore == db) {
		if (configured_emulator != emulator) {
			db = nullptr;
			return godot::ERR_ALREADY_IN_USE;
		}
		return godot::OK;
	}
	if (!emulator.empty()) {
		firebase::firestore::Settings settings = db->settings();
		settings.set_host(emulator);
		settings.set_ssl_enabled(false);
		db->set_settings(settings);
	}
	configured_firestore = db;
	configured_emulator = emulator;
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
		const String reason = to_map_field_value(document.firestore(), p_data, p_merge, fields);
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
		const String reason = to_update_field_value(document.firestore(), p_data, fields);
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

int64_t FirebaseFirestoreNative::run_query(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const String &p_source, const Dictionary &p_cursor) {
	return start_query(p_collection, p_filters, p_order_by, p_limit, p_source, p_cursor, false);
}

int64_t FirebaseFirestoreNative::run_query_snapshot(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const String &p_source, const Dictionary &p_cursor) {
	return start_query(p_collection, p_filters, p_order_by, p_limit, p_source, p_cursor, true);
}

int64_t FirebaseFirestoreNative::run_count(const String &p_collection, const Array &p_filters) {
	return start([&](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
			return;
		}
		Query query;
		const String reason = to_query(db, p_collection, p_filters, Array(), 0, Dictionary(), query);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(query.Count().Get(AggregateSource::kServer), std::move(done), [](const Future<AggregateQuerySnapshot> &future) {
			return Variant(future.result()->count());
		});
	});
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

int64_t FirebaseFirestoreNative::start_query(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const String &p_source, const Dictionary &p_cursor, bool p_with_metadata) {
	return start([&](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFirestoreNative is not initialized"));
			return;
		}
		Source source;
		if (!parse_source(p_source, source)) {
			done(invalid("source must be default, cache, or server"));
			return;
		}
		Query query;
		const String reason = to_query(db, p_collection, p_filters, p_order_by, p_limit, p_cursor, query);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(query.Get(source), std::move(done), [p_with_metadata](const Future<QuerySnapshot> &future) {
			const Dictionary result = to_query_snapshot(*future.result());
			return p_with_metadata ? Variant(result) : result["documents"];
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

int64_t FirebaseFirestoreNative::listen_query(const String &p_collection, const Array &p_filters, const Array &p_order_by, int64_t p_limit, const Dictionary &p_cursor, bool p_include_metadata_changes) {
	Query query;
	if (db == nullptr || !to_query(db, p_collection, p_filters, p_order_by, p_limit, p_cursor, query).is_empty()) {
		return 0;
	}
	const int64_t id = ++next_listener_id;
	const uint64_t object_id = get_instance_id();
	listeners[id] = query.AddSnapshotListener(
			p_include_metadata_changes ? MetadataChanges::kInclude : MetadataChanges::kExclude,
			[object_id, id](const QuerySnapshot &snapshot, firebase::firestore::Error error, const std::string &message) {
				const bool ok = error == firebase::firestore::kErrorOk;
				const Array args = Array::make(id, ok, ok ? to_query_snapshot(snapshot) : Dictionary(), static_cast<int>(error), to_godot(message));
				emit_deferred_to(object_id, "query_changed", args);
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
	godot::ClassDB::bind_method(D_METHOD("initialize", "emulator_host"), &FirebaseFirestoreNative::initialize, DEFVAL(""));
	godot::ClassDB::bind_method(D_METHOD("get_doc", "path", "source"), &FirebaseFirestoreNative::get_doc, DEFVAL("default"));
	godot::ClassDB::bind_method(D_METHOD("set_doc", "path", "data", "merge"), &FirebaseFirestoreNative::set_doc);
	godot::ClassDB::bind_method(D_METHOD("update_doc", "path", "data"), &FirebaseFirestoreNative::update_doc);
	godot::ClassDB::bind_method(D_METHOD("delete_doc", "path"), &FirebaseFirestoreNative::delete_doc);
	godot::ClassDB::bind_method(D_METHOD("run_query", "collection_path", "filters", "order_by", "limit", "source", "cursor"), &FirebaseFirestoreNative::run_query, DEFVAL("default"), DEFVAL(Dictionary()));
	godot::ClassDB::bind_method(D_METHOD("run_query_snapshot", "collection_path", "filters", "order_by", "limit", "source", "cursor"), &FirebaseFirestoreNative::run_query_snapshot, DEFVAL("default"), DEFVAL(Dictionary()));
	godot::ClassDB::bind_method(D_METHOD("run_count", "collection_path", "filters"), &FirebaseFirestoreNative::run_count);
	godot::ClassDB::bind_method(D_METHOD("set_network_enabled", "enabled"), &FirebaseFirestoreNative::set_network_enabled);
	godot::ClassDB::bind_method(D_METHOD("wait_pending_writes"), &FirebaseFirestoreNative::wait_pending_writes);
	godot::ClassDB::bind_method(D_METHOD("commit_batch", "ops"), &FirebaseFirestoreNative::commit_batch);
	godot::ClassDB::bind_method(D_METHOD("listen_doc", "path", "include_metadata_changes"), &FirebaseFirestoreNative::listen_doc, DEFVAL(false));
	godot::ClassDB::bind_method(D_METHOD("listen_query", "collection_path", "filters", "order_by", "limit", "cursor", "include_metadata_changes"), &FirebaseFirestoreNative::listen_query, DEFVAL(Dictionary()), DEFVAL(false));
	godot::ClassDB::bind_method(D_METHOD("remove_listener", "id"), &FirebaseFirestoreNative::remove_listener);
	for (const char *signal : { "document_changed", "query_changed" }) {
		ADD_SIGNAL(godot::MethodInfo(signal,
				godot::PropertyInfo(Variant::INT, "listener_id"), godot::PropertyInfo(Variant::BOOL, "ok"),
				godot::PropertyInfo(Variant::DICTIONARY, "snapshot"), godot::PropertyInfo(Variant::INT, "error_code"),
				godot::PropertyInfo(Variant::STRING, "error_message")));
	}
}

} // namespace godot_firebase
