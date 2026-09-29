#include "firebase_database_native.h"

#include <string>
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

// Same rules as FirebaseDatabase.is_valid_key() and is_valid_path().
// The SDK aborts on these characters.
bool is_valid_key(const std::string &p_key) {
	return !p_key.empty() && p_key.find_first_of(".#$[]/") == std::string::npos;
}

bool is_valid_path(const String &p_path) {
	if (p_path.is_empty()) {
		return true;
	}
	const godot::PackedStringArray keys = p_path.split("/");
	for (int64_t i = 0; i < keys.size(); i++) {
		if (!is_valid_key(to_std(keys[i]))) {
			return false;
		}
	}
	return true;
}

// Checks the keys of converted maps; FirebaseDatabase.SERVER_TIMESTAMP is allowed.
String check_keys(const firebase::Variant &p_value) {
	if (p_value.is_vector()) {
		for (const firebase::Variant &item : p_value.vector()) {
			const String reason = check_keys(item);
			if (!reason.is_empty()) {
				return reason;
			}
		}
	} else if (p_value.is_map() && p_value != firebase::database::ServerTimestamp()) {
		for (const auto &entry : p_value.map()) {
			if (!is_valid_key(entry.first.string_value())) {
				return "keys must be strings without . # $ [ ] /: " + String::utf8(entry.first.string_value());
			}
			const String reason = check_keys(entry.second);
			if (!reason.is_empty()) {
				return reason;
			}
		}
	}
	return String();
}

// Returns an empty string when `p_value` can be written, otherwise the reason.
String to_database_value(const Variant &p_value, firebase::Variant &r_out) {
	const String reason = to_firebase_variant(p_value, r_out);
	return reason.is_empty() ? check_keys(r_out) : reason;
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

FirebaseDatabaseNative::FirebaseDatabaseNative() = default;
FirebaseDatabaseNative::~FirebaseDatabaseNative() = default;

godot::Error FirebaseDatabaseNative::initialize() {
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
	return godot::OK;
}

DatabaseReference FirebaseDatabaseNative::reference(const String &p_path) const {
	return p_path.is_empty() ? db->GetReference() : db->GetReference(to_std(p_path).c_str());
}

int64_t FirebaseDatabaseNative::start_with_reference(const String &p_path, const std::function<void(DatabaseReference, Completion)> &p_request) {
	return start([this, &p_path, &p_request](Completion done) {
		if (db == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseDatabaseNative is not initialized"));
		} else if (!is_valid_path(p_path)) {
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
	});
}

int64_t FirebaseDatabaseNative::set_value(const String &p_path, const Variant &p_value) {
	return start_with_reference(p_path, [&p_value](DatabaseReference target, Completion done) {
		firebase::Variant value;
		const String reason = to_database_value(p_value, value);
		if (!reason.is_empty()) {
			done(invalid(reason));
			return;
		}
		complete_when_done(target.SetValue(value), std::move(done));
	});
}

int64_t FirebaseDatabaseNative::update_children(const String &p_path, const Dictionary &p_values) {
	return start_with_reference(p_path, [&p_values](DatabaseReference target, Completion done) {
		const Array children = p_values.keys();
		for (int64_t i = 0; i < children.size(); i++) {
			const Variant child = children[i];
			const bool is_text = child.get_type() == Variant::STRING || child.get_type() == Variant::STRING_NAME;
			if (!is_text || String(child).is_empty() || !is_valid_path(child)) {
				done(invalid("child path must be a non-empty valid path: " + String(child)));
				return;
			}
		}
		firebase::Variant values = firebase::Variant::EmptyMap();
		for (int64_t i = 0; i < children.size(); i++) {
			firebase::Variant value;
			const String reason = to_database_value(p_values[children[i]], value);
			if (!reason.is_empty()) {
				done(invalid(reason));
				return;
			}
			values.map()[firebase::Variant(to_std(children[i]))] = std::move(value);
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
	return start_with_reference(p_path, [&p_value](DatabaseReference target, Completion done) {
		firebase::Variant value;
		const String reason = to_database_value(p_value, value);
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

int64_t FirebaseDatabaseNative::listen_value(const String &p_path) {
	if (db == nullptr || !is_valid_path(p_path)) {
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
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseDatabaseNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("get_value", "path"), &FirebaseDatabaseNative::get_value);
	godot::ClassDB::bind_method(D_METHOD("set_value", "path", "value"), &FirebaseDatabaseNative::set_value);
	godot::ClassDB::bind_method(D_METHOD("update_children", "path", "values"), &FirebaseDatabaseNative::update_children);
	godot::ClassDB::bind_method(D_METHOD("remove_value", "path"), &FirebaseDatabaseNative::remove_value);
	godot::ClassDB::bind_method(D_METHOD("push_value", "path", "value"), &FirebaseDatabaseNative::push_value);
	godot::ClassDB::bind_method(D_METHOD("listen_value", "path"), &FirebaseDatabaseNative::listen_value);
	godot::ClassDB::bind_method(D_METHOD("remove_listener", "id"), &FirebaseDatabaseNative::remove_listener);
	ADD_SIGNAL(godot::MethodInfo("value_changed",
			godot::PropertyInfo(Variant::INT, "listener_id"), godot::PropertyInfo(Variant::BOOL, "ok"),
			godot::PropertyInfo(Variant::DICTIONARY, "snapshot"), godot::PropertyInfo(Variant::INT, "error_code"),
			godot::PropertyInfo(Variant::STRING, "error_message")));
}

} // namespace godot_firebase
