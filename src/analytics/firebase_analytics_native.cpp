#include "firebase_analytics_native.h"
#include <cmath>
#include <map>
#include <set>
#include <vector>
#include <firebase/analytics.h>
#include <godot_cpp/core/class_db.hpp>
#include "../core/firebase_app_native.h"

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::Variant;
namespace godot_firebase {
namespace {
std::set<FirebaseAnalyticsNative *> instances;
// Pinned Firebase iOS 12.19.1 FIRAnalytics.h. Suggested public events remain allowed.
const std::set<std::string> reserved_events = {
	"ad_activeview", "ad_click", "ad_exposure", "ad_query", "ad_reward", "adunit_exposure",
	"app_clear_data", "app_exception", "app_remove", "app_store_refund", "app_store_subscription_cancel",
	"app_store_subscription_convert", "app_store_subscription_renew", "app_update", "app_upgrade",
	"dynamic_link_app_open", "dynamic_link_app_update", "dynamic_link_first_open", "error",
	"firebase_campaign", "first_open", "first_visit", "notification_dismiss", "notification_foreground",
	"notification_open", "notification_receive", "os_update", "session_start", "session_start_with_rollout", "user_engagement"
};
const std::map<std::string, firebase::analytics::ConsentType> consent_keys = {
	{"analytics_storage", firebase::analytics::kConsentTypeAnalyticsStorage},
	{"ad_storage", firebase::analytics::kConsentTypeAdStorage},
	{"ad_user_data", firebase::analytics::kConsentTypeAdUserData},
	{"ad_personalization", firebase::analytics::kConsentTypeAdPersonalization}
};
bool has_null(const String &p_value) {
	for (int64_t i = 0; i < p_value.length(); i++) {
		if (p_value[i] == 0) return true;
	}
	return false;
}
String validate_name(const String &p_name, int p_limit) {
	if (p_name.is_empty() || p_name.length() > p_limit) return "invalid Analytics name length";
	for (int64_t i = 0; i < p_name.length(); i++) {
		const char32_t c = p_name[i];
		const bool letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
		if (!letter && (i == 0 || !((c >= '0' && c <= '9') || c == '_'))) return "Analytics names must start with an ASCII letter and contain letters, digits or underscores";
	}
	if (p_name.begins_with("firebase_") || p_name.begins_with("google_") || p_name.begins_with("ga_")) return "reserved Analytics name prefix";
	return String();
}
String validate_property(const String &p_name) {
	if (p_name == "first_open_time" || p_name == "last_deep_link_referrer" || p_name == "user_id") return "reserved user property";
	return validate_name(p_name, 24);
}
String validate_event(const String &p_name, const Dictionary &p_parameters) {
	String reason = validate_name(p_name, 40);
	if (!reason.is_empty()) return reason;
	if (reserved_events.count(to_std(p_name))) return "reserved event name";
	if (p_parameters.size() > 25) return "events accept at most 25 parameters";
	const Array keys = p_parameters.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		if (keys[i].get_type() != Variant::STRING) return "parameter keys must be strings";
		reason = validate_name(keys[i], 40);
		if (!reason.is_empty()) return reason;
		const Variant value = p_parameters[keys[i]];
		switch (value.get_type()) {
			case Variant::STRING:
				if (String(value).length() > 100 || has_null(value)) return "parameter strings accept at most 100 characters without NUL";
				break;
			case Variant::INT: break;
			case Variant::FLOAT:
				if (!std::isfinite(static_cast<double>(value))) return "parameter numbers must be finite";
				break;
			default: return "parameter values must be String, int or finite float";
		}
	}
	return String();
}
} // namespace

godot::Error FirebaseAnalyticsNative::initialize() {
	if (initialized) return godot::ERR_ALREADY_IN_USE;
	firebase::App *app = FirebaseAppNative::get_app();
	if (!app) return godot::ERR_UNCONFIGURED;
	if (instances.empty()) firebase::analytics::Initialize(*app);
	instances.insert(this);
	initialized = true;
	return godot::OK;
}
FirebaseAnalyticsNative::~FirebaseAnalyticsNative() {
	if (!initialized) return;
	instances.erase(this);
	if (instances.empty()) firebase::analytics::Terminate();
}
void FirebaseAnalyticsNative::shutdown_all() {
	if (instances.empty()) return;
	for (auto *instance : instances) instance->initialized = false;
	instances.clear();
	firebase::analytics::Terminate();
}
int64_t FirebaseAnalyticsNative::apply(const std::function<void()> &p_action, const String &p_reason) {
	return start([this, &p_action, &p_reason](Completion done) {
		if (!initialized) { done(Outcome::failure(kUnavailable, "Analytics is not initialized")); return; }
		if (!p_reason.is_empty()) { done(Outcome::failure(kInvalidArgument, p_reason)); return; }
		p_action();
		done(Outcome::success());
	});
}
int64_t FirebaseAnalyticsNative::log_event(const String &p_name, const Dictionary &p_parameters) {
	return apply([&]() {
		const Array keys = p_parameters.keys();
		std::vector<std::string> names;
		std::vector<firebase::analytics::Parameter> parameters;
		names.reserve(keys.size()); parameters.reserve(keys.size());
		for (int64_t i = 0; i < keys.size(); i++) {
			names.push_back(to_std(keys[i]));
			const Variant value = p_parameters[keys[i]];
			firebase::Variant converted;
			if (value.get_type() == Variant::STRING) converted = firebase::Variant(to_std(value));
			else if (value.get_type() == Variant::INT) converted = firebase::Variant(static_cast<int64_t>(value));
			else converted = firebase::Variant(static_cast<double>(value));
			parameters.emplace_back(names.back().c_str(), std::move(converted));
		}
		firebase::analytics::LogEvent(to_std(p_name).c_str(), parameters);
	}, validate_event(p_name, p_parameters));
}
int64_t FirebaseAnalyticsNative::set_user_id(const String &p_id) {
	return apply([&]() { firebase::analytics::SetUserId(to_std(p_id).c_str()); }, p_id.is_empty() || p_id.length() > 256 || has_null(p_id) ? String("user_id must contain 1..256 characters") : String());
}
int64_t FirebaseAnalyticsNative::clear_user_id() {
	return apply([]() { firebase::analytics::SetUserId(nullptr); });
}
int64_t FirebaseAnalyticsNative::set_user_property(const String &p_name, const String &p_value) {
	String reason = validate_property(p_name);
	if (reason.is_empty() && (p_value.length() > 36 || has_null(p_value))) reason = "user property value accepts at most 36 characters without NUL";
	return apply([&]() { firebase::analytics::SetUserProperty(to_std(p_name).c_str(), to_std(p_value).c_str()); }, reason);
}
int64_t FirebaseAnalyticsNative::clear_user_property(const String &p_name) {
	return apply([&]() { firebase::analytics::SetUserProperty(to_std(p_name).c_str(), nullptr); }, validate_property(p_name));
}
int64_t FirebaseAnalyticsNative::set_collection_enabled(bool p_enabled) {
	return apply([&]() { firebase::analytics::SetAnalyticsCollectionEnabled(p_enabled); });
}
int64_t FirebaseAnalyticsNative::set_consent(const Dictionary &p_consents) {
	std::map<firebase::analytics::ConsentType, firebase::analytics::ConsentStatus> converted;
	String reason;
	const Array keys = p_consents.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant value = p_consents[keys[i]];
		if (keys[i].get_type() != Variant::STRING || !consent_keys.count(to_std(keys[i]))) { reason = "unknown consent key"; break; }
		if (value.get_type() != Variant::INT || (static_cast<int64_t>(value) != 0 && static_cast<int64_t>(value) != 1)) { reason = "consent must be GRANTED or DENIED"; break; }
		converted[consent_keys.at(to_std(keys[i]))] = static_cast<firebase::analytics::ConsentStatus>(static_cast<int64_t>(value));
	}
	return apply([&]() { firebase::analytics::SetConsent(converted); }, reason);
}
int64_t FirebaseAnalyticsNative::reset_analytics_data() {
	return apply([]() { firebase::analytics::ResetAnalyticsData(); });
}
void FirebaseAnalyticsNative::_bind_methods() {
	using godot::D_METHOD;
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseAnalyticsNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("log_event", "name", "parameters"), &FirebaseAnalyticsNative::log_event, DEFVAL(Dictionary()));
	godot::ClassDB::bind_method(D_METHOD("set_user_id", "user_id"), &FirebaseAnalyticsNative::set_user_id);
	godot::ClassDB::bind_method(D_METHOD("clear_user_id"), &FirebaseAnalyticsNative::clear_user_id);
	godot::ClassDB::bind_method(D_METHOD("set_user_property", "name", "value"), &FirebaseAnalyticsNative::set_user_property);
	godot::ClassDB::bind_method(D_METHOD("clear_user_property", "name"), &FirebaseAnalyticsNative::clear_user_property);
	godot::ClassDB::bind_method(D_METHOD("set_collection_enabled", "enabled"), &FirebaseAnalyticsNative::set_collection_enabled);
	godot::ClassDB::bind_method(D_METHOD("set_consent", "consents"), &FirebaseAnalyticsNative::set_consent);
	godot::ClassDB::bind_method(D_METHOD("reset_analytics_data"), &FirebaseAnalyticsNative::reset_analytics_data);
}
} // namespace godot_firebase
