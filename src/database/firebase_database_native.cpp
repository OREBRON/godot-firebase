#include "firebase_database_native.h"

#include <cmath>
#include <string>
#include <unordered_set>
#include <utility>

#include <godot_cpp/core/class_db.hpp>

#include "../core/firebase_app_native.h"
#include "../core/variant_convert.h"

using firebase::Future;
using firebase::database::DatabaseReference;
using firebase::database::DataSnapshot;
using godot::Array;
using godot::D_METHOD;
using godot::Dictionary;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

constexpr int kMaxDepth = 32;
firebase::database::Database *configured_database = nullptr;
bool configured_persistence = false;
std::unordered_set<FirebaseDatabaseNative *> active_modules;

// Same rules as FirebaseDatabase.is_valid_key() and is_valid_path().
// The SDK aborts on these characters.
bool is_valid_key(const std::string &p_key) {
	if (p_key.empty() || p_key.size() > 768 || p_key.find_first_of(".#$[]/") != std::string::npos) {
		return false;
	}
	for (unsigned char character : p_key) {
		if (character < 32 || character == 127) {
			return false;
		}
	}
	return true;
}

int path_depth(const String &p_path) {
	return p_path.is_empty() ? 0 : p_path.split("/").size();
}

bool is_valid_path(const String &p_path) {
	if (p_path.is_empty()) {
		return true;
	}
	const godot::PackedStringArray keys = p_path.split("/");
	if (keys.size() > kMaxDepth) {
		return false;
	}
	for (int64_t i = 0; i < keys.size(); i++) {
		if (!is_valid_key(to_std(keys[i]))) {
			return false;
		}
	}
	return true;
}

bool is_readable_path(const String &p_path) {
	return p_path == ".info/connected" || p_path == ".info/serverTimeOffset" || is_valid_path(p_path);
}

// Validate before conversion. The depth bound also stops cycles before C++ recursion
// can exhaust the stack; the common converter independently guards cycles/depth.
String validate_value(const Variant &p_value, int p_depth) {
	if (p_depth > kMaxDepth) {
		return "database paths and values must not exceed 32 levels";
	}
	switch (p_value.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::STRING:
		case Variant::STRING_NAME:
			return String();
		case Variant::FLOAT:
			return std::isfinite(static_cast<double>(p_value)) ? String() : String("database numbers must be finite");
		case Variant::ARRAY:
		case Variant::PACKED_INT32_ARRAY:
		case Variant::PACKED_INT64_ARRAY:
		case Variant::PACKED_FLOAT32_ARRAY:
		case Variant::PACKED_FLOAT64_ARRAY:
		case Variant::PACKED_STRING_ARRAY: {
			const Array items = p_value;
			for (int64_t i = 0; i < items.size(); i++) {
				const String reason = validate_value(items[i], p_depth + 1);
				if (!reason.is_empty()) {
					return reason;
				}
			}
			return String();
		}
		case Variant::DICTIONARY: {
			const Dictionary entries = p_value;
			const Variant marker = entries.get(".sv", Variant());
			if (entries.size() == 1 && marker.get_type() == Variant::STRING && String(marker) == "timestamp") {
				return String();
			}
			const Array keys = entries.keys();
			for (int64_t i = 0; i < keys.size(); i++) {
				const Variant key = keys[i];
				if (key.get_type() != Variant::STRING || !is_valid_key(to_std(key))) {
					return "keys must be strings without . # $ [ ] /";
				}
				const String reason = validate_value(entries[key], p_depth + 1);
				if (!reason.is_empty()) {
					return reason;
				}
			}
			return String();
		}
		default:
			return "unsupported type " + Variant::get_type_name(p_value.get_type());
	}
}

// Returns an empty string when `p_value` can be written, otherwise the reason.
String to_database_value(const Variant &p_value, firebase::Variant &r_out, int p_depth) {
	const String reason = validate_value(p_value, p_depth);
	return reason.is_empty() ? to_firebase_variant(p_value, r_out) : reason;
}

String to_database_updates(const Dictionary &p_values, int p_depth, firebase::Variant &r_out) {
	r_out = firebase::Variant::EmptyMap();
	const Array children = p_values.keys();
	for (int64_t i = 0; i < children.size(); i++) {
		const Variant child = children[i];
		if (child.get_type() != Variant::STRING || String(child).is_empty() || !is_valid_path(child)) {
			return "child path must be a non-empty valid path";
		}
		const std::string child_path = to_std(child);
		for (size_t slash = child_path.find('/'); slash != std::string::npos; slash = child_path.find('/', slash + 1)) {
			if (p_values.has(to_godot(child_path.substr(0, slash)))) {
				return "update paths must not contain both a parent and its child";
			}
		}
		firebase::Variant value;
		const String reason = to_database_value(p_values[child], value, p_depth + path_depth(child));
		if (!reason.is_empty()) {
			return reason;
		}
		r_out.map()[firebase::Variant(to_std(child))] = std::move(value);
	}
	return String();
}

Outcome invalid(const String &p_reason) {
	return Outcome::failure(kInvalidArgument, p_reason);
}

Dictionary to_snapshot(const DataSnapshot &p_snapshot) {
	const char *key = p_snapshot.key();
	Dictionary snapshot;
	snapshot["key"] = key ? String::utf8(key) : String();
	snapshot["exists"] = p_snapshot.exists();
	snapshot["value"] = to_godot_variant(p_snapshot.value());
	return snapshot;
}

} // namespace

// Emits value_changed for one listen_value() call. Nested to reach emit_deferred_to().
class FirebaseDatabaseNative::Listener : public firebase::database::ValueListener {
public:
	Listener(uint64_t p_object_id, int64_t p_id, DatabaseReference p_reference) :
			object_id(p_object_id), id(p_id), target(std::move(p_reference)) {
		target.AddValueListener(this);
	}

	~Listener() override {
		target.RemoveValueListener(this);
	}

	void OnValueChanged(const DataSnapshot &p_snapshot) override {
		emit_deferred_to(object_id, "value_changed", Array::make(id, true, to_snapshot(p_snapshot), 0, String()));
	}

	void OnCancelled(const firebase::database::Error &p_error, const char *p_message) override {
		const String message = String::utf8(p_message ? p_message : "listener cancelled");
		emit_deferred_to(object_id, "value_changed", Array::make(id, false, Dictionary(), static_cast<int>(p_error), message));
	}

private:
	uint64_t object_id;
	int64_t id;
	DatabaseReference target;
};

FirebaseDatabaseNative::FirebaseDatabaseNative() {
	active_modules.insert(this);
}

FirebaseDatabaseNative::~FirebaseDatabaseNative() {
	listeners.clear();
	active_modules.erase(this);
}

void FirebaseDatabaseNative::shutdown_all() {
	for (FirebaseDatabaseNative *module : active_modules) {
		module->listeners.clear();
		module->db = nullptr;
	}
	configured_database = nullptr;
	configured_persistence = false;
}

godot::Error FirebaseDatabaseNative::initialize(bool p_persistence_enabled) {
	if (db) {
		return godot::ERR_ALREADY_IN_USE;
	}
	firebase::App *app = FirebaseAppNative::get_app();
	if (app == nullptr) {
		return godot::ERR_UNCONFIGURED;
	}
	firebase::InitResult result = firebase::kInitResultSuccess;
	db = firebase::database::Database::GetInstance(app, &result);
	if (db == nullptr || result != firebase::kInitResultSuccess) {
		db = nullptr;
		return godot::ERR_CANT_CREATE;
	}
	// Database is shared by all wrappers. Never repeat this SDK setting after
	// another wrapper has created a reference. Core owns the App for this process.
	if (configured_database == db) {
		if (configured_persistence != p_persistence_enabled) {
			db = nullptr;
			return godot::ERR_ALREADY_IN_USE;
		}
		return godot::OK;
	}
	db->set_persistence_enabled(p_persistence_enabled);
	configured_database = db;
	configured_persistence = p_persistence_enabled;
	return godot::OK;
}

int64_t FirebaseDatabaseNative::set_network_enabled(bool p_enabled) {
	return start([this, p_enabled](Completion done) {
		if (!db) {
			done(Outcome::failure(kUnavailable, "FirebaseDatabaseNative is not initialized"));
			return;
		}
		if (p_enabled) {
			db->GoOnline();
		} else {
			db->GoOffline();
		}
		done(Outcome::success());
	});
}

DatabaseReference FirebaseDatabaseNative::reference(const String &p_path) const {
	return p_path.is_empty() ? db->GetReference() : db->GetReference(to_std(p_path).c_str());
}

int64_t FirebaseDatabaseNative::start_with_reference(const String &p_path, const std::function<void(DatabaseReference, Completion)> &p_request, bool p_allow_info) {
	return start([this, &p_path, &p_request, p_allow_info](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseDatabaseNative is not initialized"));
		} else if (!(p_allow_info ? is_readable_path(p_path) : is_valid_path(p_path))) {
			done(invalid("not a database path: " + p_path));
		} else {
			p_request(reference(p_path), std::move(done));
		}
	});
}

int64_t FirebaseDatabaseNative::get_value(const String &p_path) {
	return start_with_reference(p_path, [](DatabaseReference target, Completion done) {
		complete_when_done(target.GetValue(), std::move(done), [](const Future<DataSnapshot> &future) {
			return Variant(to_snapshot(*future.result()));
		});
	}, true);
}

int64_t FirebaseDatabaseNative::set_value(const String &p_path, const Variant &p_value) {
	return start_with_reference(p_path, [&p_value, &p_path](DatabaseReference target, Completion done) {
		firebase::Variant value;
		const String reason = to_database_value(p_value, value, path_depth(p_path));
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(target.SetValue(value), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::update_children(const String &p_path, const Dictionary &p_values) {
	return start_with_reference(p_path, [&p_values, &p_path](DatabaseReference target, Completion done) {
		firebase::Variant values;
		const String reason = to_database_updates(p_values, path_depth(p_path), values);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(target.UpdateChildren(values), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::remove_value(const String &p_path) {
	return start_with_reference(p_path, [](DatabaseReference target, Completion done) {
		complete_when_done(target.RemoveValue(), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::push_value(const String &p_path, const Variant &p_value) {
	return start_with_reference(p_path, [&p_value, &p_path](DatabaseReference target, Completion done) {
		firebase::Variant value;
		const String reason = to_database_value(p_value, value, path_depth(p_path) + 1);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		DatabaseReference child = target.PushChild();
		complete_when_done(child.SetValue(value), std::move(done), [key = child.key_string()](const Future<void> &) {
			return Variant(to_godot(key));
		});
	});
}

int64_t FirebaseDatabaseNative::on_disconnect_set_value(const String &p_path, const Variant &p_value) {
	return start_with_reference(p_path, [&p_value, &p_path](DatabaseReference target, Completion done) {
		firebase::Variant value;
		const String reason = to_database_value(p_value, value, path_depth(p_path));
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(target.OnDisconnect()->SetValue(value), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::on_disconnect_update_children(const String &p_path, const Dictionary &p_values) {
	return start_with_reference(p_path, [&p_values, &p_path](DatabaseReference target, Completion done) {
		firebase::Variant values;
		const String reason = to_database_updates(p_values, path_depth(p_path), values);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(target.OnDisconnect()->UpdateChildren(values), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::on_disconnect_remove_value(const String &p_path) {
	return start_with_reference(p_path, [](DatabaseReference target, Completion done) {
		complete_when_done(target.OnDisconnect()->RemoveValue(), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::on_disconnect_cancel(const String &p_path) {
	return start_with_reference(p_path, [](DatabaseReference target, Completion done) {
		complete_when_done(target.OnDisconnect()->Cancel(), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::listen_value(const String &p_path) {
	if (db == nullptr || !is_readable_path(p_path)) {
		return 0;
	}
	const int64_t id = ++next_listener_id;
	listeners[id] = std::make_unique<Listener>(get_instance_id(), id, reference(p_path));
	return id;
}

void FirebaseDatabaseNative::remove_listener(int64_t p_id) {
	listeners.erase(p_id);
}

void FirebaseDatabaseNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize", "persistence_enabled"), &FirebaseDatabaseNative::initialize, DEFVAL(false));
	godot::ClassDB::bind_method(D_METHOD("set_network_enabled", "enabled"), &FirebaseDatabaseNative::set_network_enabled);
	godot::ClassDB::bind_method(D_METHOD("get_value", "path"), &FirebaseDatabaseNative::get_value);
	godot::ClassDB::bind_method(D_METHOD("set_value", "path", "value"), &FirebaseDatabaseNative::set_value);
	godot::ClassDB::bind_method(D_METHOD("update_children", "path", "values"), &FirebaseDatabaseNative::update_children);
	godot::ClassDB::bind_method(D_METHOD("remove_value", "path"), &FirebaseDatabaseNative::remove_value);
	godot::ClassDB::bind_method(D_METHOD("push_value", "path", "value"), &FirebaseDatabaseNative::push_value);
	godot::ClassDB::bind_method(D_METHOD("on_disconnect_set_value", "path", "value"), &FirebaseDatabaseNative::on_disconnect_set_value);
	godot::ClassDB::bind_method(D_METHOD("on_disconnect_update_children", "path", "values"), &FirebaseDatabaseNative::on_disconnect_update_children);
	godot::ClassDB::bind_method(D_METHOD("on_disconnect_remove_value", "path"), &FirebaseDatabaseNative::on_disconnect_remove_value);
	godot::ClassDB::bind_method(D_METHOD("on_disconnect_cancel", "path"), &FirebaseDatabaseNative::on_disconnect_cancel);
	godot::ClassDB::bind_method(D_METHOD("listen_value", "path"), &FirebaseDatabaseNative::listen_value);
	godot::ClassDB::bind_method(D_METHOD("remove_listener", "id"), &FirebaseDatabaseNative::remove_listener);
	ADD_SIGNAL(godot::MethodInfo("value_changed",
			godot::PropertyInfo(Variant::INT, "listener_id"), godot::PropertyInfo(Variant::BOOL, "ok"),
			godot::PropertyInfo(Variant::DICTIONARY, "snapshot"), godot::PropertyInfo(Variant::INT, "error_code"),
			godot::PropertyInfo(Variant::STRING, "error_message")));
}

} // namespace godot_firebase
