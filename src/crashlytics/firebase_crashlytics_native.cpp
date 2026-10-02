#include "firebase_crashlytics_native.h"
#include <atomic>
#include <cmath>
#include <map>
#include <mutex>
#include <set>
#include <godot_cpp/core/class_db.hpp>
#include "../core/firebase_app_native.h"
#include "platform/crashlytics_platform.h"

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::Variant;
namespace godot_firebase {
namespace {
std::set<FirebaseCrashlyticsNative *> instances;
std::mutex pending_mutex;
std::map<int64_t, Completion> pending;
std::atomic<int64_t> next_token{0};

String validate_key(const String &key, const Variant &value) {
	if (key.is_empty()) return "custom key must not be empty";
	switch (value.get_type()) {
		case Variant::STRING: case Variant::BOOL: case Variant::INT: return String();
		case Variant::FLOAT:
			return std::isfinite(static_cast<double>(value)) ? String() : String("custom numbers must be finite");
		default: return "custom values must be String, bool, int or finite float";
	}
}
String validate_error(const String &name, const Array &stack) {
	if (name.is_empty()) return "error name must not be empty";
	for (int64_t i = 0; i < stack.size(); i++) {
		if (stack[i].get_type() != Variant::DICTIONARY) return "stack frames must be dictionaries";
		const Dictionary frame = stack[i];
		if (frame.size() != 3 || frame.get("function", Variant()).get_type() != Variant::STRING ||
				frame.get("file", Variant()).get_type() != Variant::STRING || frame.get("line", Variant()).get_type() != Variant::INT)
			return "stack frames require exactly String function/file and int line";
		const int64_t line = frame["line"];
		if (line < 0 || line > INT32_MAX) return "stack frame line must fit a non-negative signed 32-bit integer";
	}
	return String();
}
Dictionary payload(const char *key, const Variant &value) {
	Dictionary result;
	result[key] = value;
	return result;
}
} // namespace

void finish_crashlytics_request(int64_t id, Outcome result) {
	Completion done;
	{
		std::lock_guard<std::mutex> lock(pending_mutex);
		auto found = pending.find(id);
		if (found == pending.end()) return;
		done = std::move(found->second);
		pending.erase(found);
	}
	done(std::move(result));
}
godot::Error FirebaseCrashlyticsNative::initialize() {
	if (initialized) return godot::ERR_ALREADY_IN_USE;
	if (!FirebaseAppNative::get_app()) return godot::ERR_UNCONFIGURED;
	const godot::Error error = initialize_crashlytics_platform();
	if (error != godot::OK) return error;
	initialized = true;
	instances.insert(this);
	return godot::OK;
}
FirebaseCrashlyticsNative::~FirebaseCrashlyticsNative() { instances.erase(this); }
void FirebaseCrashlyticsNative::shutdown_all() {
	for (auto *instance : instances) instance->initialized = false;
	instances.clear();
	std::map<int64_t, Completion> cancelled;
	{
		std::lock_guard<std::mutex> lock(pending_mutex);
		cancelled.swap(pending);
	}
	for (auto &entry : cancelled) entry.second(Outcome::failure(kCancelled, "Crashlytics shut down"));
}
int64_t FirebaseCrashlyticsNative::apply(const String &operation, const Dictionary &data, const String &reason) {
	return start([&](Completion done) {
		if (!reason.is_empty()) { done(Outcome::failure(kInvalidArgument, reason)); return; }
		if (!initialized) { done(Outcome::failure(kUnavailable, "Crashlytics is not initialized")); return; }
		const int64_t token = ++next_token;
		{
			std::lock_guard<std::mutex> lock(pending_mutex);
			pending.emplace(token, std::move(done));
		}
		dispatch_crashlytics(operation, data, token);
	});
}
int64_t FirebaseCrashlyticsNative::log_message(const String &message) { return apply("log_message", payload("message", message)); }
int64_t FirebaseCrashlyticsNative::set_custom_key(const String &key, const Variant &value) {
	Dictionary data = payload("key", key);
	data["value"] = value;
	return apply("set_custom_key", data, validate_key(key, value));
}
int64_t FirebaseCrashlyticsNative::set_user_id(const String &user_id) { return apply("set_user_id", payload("user_id", user_id)); }
int64_t FirebaseCrashlyticsNative::clear_user_id() { return set_user_id(""); }
int64_t FirebaseCrashlyticsNative::record_error(const String &name, const String &message, const godot::TypedArray<Dictionary> &stack) {
	Dictionary data = payload("name", name);
	data["message"] = message;
	data["stack"] = stack;
	return apply("record_error", data, validate_error(name, stack));
}
int64_t FirebaseCrashlyticsNative::set_collection_enabled(bool enabled) { return apply("set_collection_enabled", payload("enabled", enabled)); }
int64_t FirebaseCrashlyticsNative::is_collection_enabled() { return apply("is_collection_enabled"); }
int64_t FirebaseCrashlyticsNative::did_crash_previous_execution() { return apply("did_crash_previous_execution"); }
int64_t FirebaseCrashlyticsNative::check_unsent_reports() { return apply("check_unsent_reports"); }
int64_t FirebaseCrashlyticsNative::send_unsent_reports() { return apply("send_unsent_reports"); }
int64_t FirebaseCrashlyticsNative::delete_unsent_reports() { return apply("delete_unsent_reports"); }

void FirebaseCrashlyticsNative::_bind_methods() {
	using godot::D_METHOD;
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseCrashlyticsNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("log_message", "message"), &FirebaseCrashlyticsNative::log_message);
	godot::ClassDB::bind_method(D_METHOD("set_custom_key", "key", "value"), &FirebaseCrashlyticsNative::set_custom_key);
	godot::ClassDB::bind_method(D_METHOD("set_user_id", "user_id"), &FirebaseCrashlyticsNative::set_user_id);
	godot::ClassDB::bind_method(D_METHOD("clear_user_id"), &FirebaseCrashlyticsNative::clear_user_id);
	godot::ClassDB::bind_method(D_METHOD("record_error", "name", "message", "stack"), &FirebaseCrashlyticsNative::record_error, DEFVAL(godot::TypedArray<Dictionary>()));
	godot::ClassDB::bind_method(D_METHOD("set_collection_enabled", "enabled"), &FirebaseCrashlyticsNative::set_collection_enabled);
	godot::ClassDB::bind_method(D_METHOD("is_collection_enabled"), &FirebaseCrashlyticsNative::is_collection_enabled);
	godot::ClassDB::bind_method(D_METHOD("did_crash_previous_execution"), &FirebaseCrashlyticsNative::did_crash_previous_execution);
	godot::ClassDB::bind_method(D_METHOD("check_unsent_reports"), &FirebaseCrashlyticsNative::check_unsent_reports);
	godot::ClassDB::bind_method(D_METHOD("send_unsent_reports"), &FirebaseCrashlyticsNative::send_unsent_reports);
	godot::ClassDB::bind_method(D_METHOD("delete_unsent_reports"), &FirebaseCrashlyticsNative::delete_unsent_reports);
}
} // namespace godot_firebase
