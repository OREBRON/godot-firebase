#include "firebase_admob_native.h"

#include <atomic>
#include <chrono>
#include <map>
#include <mutex>
#include <set>
#include <utility>

#include <godot_cpp/core/class_db.hpp>

#include "../core/firebase_app_native.h"
#include "platform/admob_platform.h"

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::Variant;

namespace godot_firebase {
namespace {
// FirebaseAdmob.AD_EXPIRY_MS and FirebaseAdmob.ERROR_AD_EXPIRED.
constexpr int64_t kAdExpiryMs = 3600000;
constexpr int kErrorAdExpired = 6;

struct AdState {
	uint64_t owner = 0;
	int64_t loaded_at_ms = 0;
	bool showing = false;
};

// Bridge answers arrive on platform threads; all state below is process-wide
// like the Google Mobile Ads and UMP singletons, and guarded by state_mutex.
std::mutex state_mutex;
std::set<FirebaseAdmobNative *> instances;
std::map<int64_t, Completion> pending;
std::map<int64_t, AdState> ads;
std::atomic<int64_t> next_token{ 0 };
std::atomic<int64_t> next_ad_id{ 0 };
bool can_request_ads = false;
bool full_screen_open = false;

int64_t now_ms() {
	return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

Outcome invalid(const String &p_reason) {
	return Outcome::failure(kInvalidArgument, p_reason);
}

Outcome busy() {
	return Outcome::failure(kBusy, "another full-screen ad or consent form is open");
}

bool is_digits(const String &p_text, int64_t p_from, int64_t p_count) {
	for (int64_t i = p_from; i < p_from + p_count; i++) {
		if (p_text[i] < '0' || p_text[i] > '9') {
			return false;
		}
	}
	return true;
}

bool is_string_array(const Variant &p_value) {
	if (p_value.get_type() == Variant::PACKED_STRING_ARRAY) {
		return true;
	}
	if (p_value.get_type() != Variant::ARRAY) {
		return false;
	}
	const Array items = p_value;
	for (int64_t i = 0; i < items.size(); i++) {
		if (items[i].get_type() != Variant::STRING) {
			return false;
		}
	}
	return true;
}

bool is_one_of(const Variant &p_value, std::initializer_list<const char *> p_choices) {
	if (p_value.get_type() != Variant::STRING) {
		return false;
	}
	const String text = p_value;
	for (const char *choice : p_choices) {
		if (text == choice) {
			return true;
		}
	}
	return false;
}

// Same rules as the FirebaseAdmob validators.
String validate_ad_unit_id(const String &p_id) {
	const String prefix = "ca-app-pub-";
	const int64_t start = prefix.length();
	if (p_id.length() != start + 27 || !p_id.begins_with(prefix) || p_id[start + 16] != '/' || !is_digits(p_id, start, 16) || !is_digits(p_id, start + 17, 10)) {
		return "ad unit ID must look like ca-app-pub-0000000000000000/0000000000";
	}
	return String();
}

String validate_verification(const Dictionary &p_verification) {
	const Array keys = p_verification.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		if (!is_one_of(keys[i], { "user_id", "custom_data" }) || p_verification[keys[i]].get_type() != Variant::STRING) {
			return "verification accepts only String user_id and custom_data";
		}
	}
	return String();
}

String validate_consent_options(const Dictionary &p_options) {
	const Array keys = p_options.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant value = p_options[keys[i]];
		if (is_one_of(keys[i], { "debug_geography" }) && is_one_of(value, { "eea", "other", "regulated_us_state" })) {
			continue;
		}
		if (is_one_of(keys[i], { "test_device_hashed_ids" }) && is_string_array(value)) {
			continue;
		}
		return "consent options accept debug_geography (eea, other, regulated_us_state) and test_device_hashed_ids";
	}
	return String();
}

String validate_request_configuration(const Dictionary &p_config) {
	const Array keys = p_config.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant value = p_config[keys[i]];
		const bool valid = (is_one_of(keys[i], { "test_device_ids" }) && is_string_array(value)) ||
				(is_one_of(keys[i], { "max_ad_content_rating" }) && is_one_of(value, { "G", "PG", "T", "MA" })) ||
				(is_one_of(keys[i], { "age_restricted_treatment" }) && is_one_of(value, { "child", "teen" }));
		if (!valid) {
			return "request configuration accepts test_device_ids, max_ad_content_rating (G, PG, T, MA) and age_restricted_treatment (child, teen)";
		}
	}
	return String();
}

// Updates the consent state from a request_consent/show_privacy_options answer.
void finish_consent(Outcome &p_outcome) {
	full_screen_open = false;
	if (p_outcome.ok && p_outcome.value.get_type() == Variant::DICTIONARY) {
		can_request_ads = bool(Dictionary(p_outcome.value).get("can_request_ads", false));
	}
}
} // namespace

void finish_admob_request(int64_t p_token, Outcome p_result) {
	Completion done;
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		auto found = pending.find(p_token);
		if (found == pending.end()) {
			return;
		}
		done = std::move(found->second);
		pending.erase(found);
	}
	done(std::move(p_result));
}

void emit_admob_event(int64_t p_ad_id, const String &p_event) {
	FirebaseAdmobNative::deliver_event(p_ad_id, p_event);
}

void FirebaseAdmobNative::deliver_event(int64_t p_ad_id, const String &p_event) {
	uint64_t owner = 0;
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		auto ad = ads.find(p_ad_id);
		if (ad == ads.end() || !ad->second.showing) {
			return;
		}
		owner = ad->second.owner;
	}
	emit_deferred_to(owner, "ad_event", Array::make(p_ad_id, p_event));
}

godot::Error FirebaseAdmobNative::initialize() {
	if (initialized) {
		return godot::ERR_ALREADY_IN_USE;
	}
	if (!FirebaseAppNative::get_app()) {
		return godot::ERR_UNCONFIGURED;
	}
	const godot::Error error = initialize_admob_platform();
	if (error != godot::OK) {
		return error;
	}
	std::lock_guard<std::mutex> lock(state_mutex);
	initialized = true;
	instances.insert(this);
	return godot::OK;
}

FirebaseAdmobNative::~FirebaseAdmobNative() {
	std::set<int64_t> released;
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		instances.erase(this);
		for (auto ad = ads.begin(); ad != ads.end();) {
			if (ad->second.owner == get_instance_id() && !ad->second.showing) {
				released.insert(ad->first);
				ad = ads.erase(ad);
			} else {
				++ad;
			}
		}
	}
	for (const int64_t ad_id : released) {
		Dictionary payload;
		payload["ad_id"] = ad_id;
		dispatch_admob("release_rewarded", payload, 0);
	}
}

void FirebaseAdmobNative::shutdown_all() {
	std::map<int64_t, Completion> cancelled;
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		for (FirebaseAdmobNative *instance : instances) {
			instance->initialized = false;
		}
		instances.clear();
		cancelled.swap(pending);
		ads.clear();
		can_request_ads = false;
		full_screen_open = false;
	}
	shutdown_admob_platform();
	for (auto &entry : cancelled) {
		entry.second(Outcome::failure(kCancelled, "AdMob shut down"));
	}
}

int64_t FirebaseAdmobNative::run(const String &p_operation, const Dictionary &p_payload, const std::function<Outcome()> &p_admit, std::function<void(Outcome &)> p_finish) {
	return start([&](Completion done) {
		Outcome admitted = Outcome::success();
		int64_t token = 0;
		{
			std::lock_guard<std::mutex> lock(state_mutex);
			admitted = initialized ? p_admit() : Outcome::failure(kUnavailable, "FirebaseAdmobNative is not initialized");
			if (admitted.ok) {
				token = ++next_token;
				pending.emplace(token, [done = std::move(done), finish = std::move(p_finish)](Outcome outcome) {
					if (finish) {
						std::lock_guard<std::mutex> state_lock(state_mutex);
						finish(outcome);
					}
					done(std::move(outcome));
				});
			}
		}
		if (!admitted.ok) {
			done(std::move(admitted));
			return;
		}
		dispatch_admob(p_operation, p_payload, token);
	});
}

int64_t FirebaseAdmobNative::request_consent(const Dictionary &p_options) {
	const String reason = validate_consent_options(p_options);
	return run("request_consent", p_options, [&]() {
		if (!reason.is_empty()) {
			return invalid(reason);
		}
		if (full_screen_open) {
			return busy();
		}
		full_screen_open = true;
		return Outcome::success();
	}, finish_consent);
}

int64_t FirebaseAdmobNative::show_privacy_options() {
	return run("show_privacy_options", Dictionary(), []() {
		if (full_screen_open) {
			return busy();
		}
		full_screen_open = true;
		return Outcome::success();
	}, finish_consent);
}

int64_t FirebaseAdmobNative::reset_consent() {
	return run("reset_consent", Dictionary(), []() {
		return full_screen_open ? busy() : Outcome::success();
	}, [](Outcome &p_outcome) {
		if (p_outcome.ok) {
			can_request_ads = false;
		}
	});
}

int64_t FirebaseAdmobNative::set_request_configuration(const Dictionary &p_config) {
	const String reason = validate_request_configuration(p_config);
	return run("set_request_configuration", p_config, [&]() {
		return reason.is_empty() ? Outcome::success() : invalid(reason);
	}, nullptr);
}

int64_t FirebaseAdmobNative::load_rewarded(const String &p_ad_unit_id) {
	const String reason = validate_ad_unit_id(p_ad_unit_id);
	const int64_t ad_id = ++next_ad_id;
	const uint64_t owner = get_instance_id();
	Dictionary payload;
	payload["ad_id"] = ad_id;
	payload["ad_unit_id"] = p_ad_unit_id;
	return run("load_rewarded", payload, [&]() {
		if (!reason.is_empty()) {
			return invalid(reason);
		}
		if (!can_request_ads) {
			return Outcome::failure(kUnavailable, "ads cannot be requested; call request_consent() first and check can_request_ads");
		}
		return Outcome::success();
	}, [ad_id, owner](Outcome &p_outcome) {
		if (p_outcome.ok) {
			ads[ad_id] = AdState{ owner, now_ms(), false };
			p_outcome.value = ad_id;
		}
	});
}

int64_t FirebaseAdmobNative::show_rewarded(int64_t p_ad_id, const Dictionary &p_verification) {
	const String reason = p_ad_id > 0 ? validate_verification(p_verification) : String("ad_id must be positive");
	Dictionary payload = p_verification.duplicate();
	payload["ad_id"] = p_ad_id;
	const uint64_t owner = get_instance_id();
	bool expired = false;
	const int64_t id = run("show_rewarded", payload, [&]() {
		if (!reason.is_empty()) {
			return invalid(reason);
		}
		auto ad = ads.find(p_ad_id);
		if (ad == ads.end()) {
			return invalid("unknown or already shown ad_id; load_rewarded() a new ad");
		}
		if (full_screen_open) {
			return busy();
		}
		if (now_ms() - ad->second.loaded_at_ms > kAdExpiryMs) {
			ads.erase(ad);
			expired = true;
			emit_deferred_to(owner, "ad_event", Array::make(p_ad_id, "failed_to_show"));
			return Outcome::failure(kErrorAdExpired, "the ad expired an hour after loading; load_rewarded() a new ad");
		}
		ad->second.showing = true;
		full_screen_open = true;
		return Outcome::success();
	}, [p_ad_id](Outcome &) {
		ads.erase(p_ad_id);
		full_screen_open = false;
	});
	if (expired) {
		Dictionary release;
		release["ad_id"] = p_ad_id;
		dispatch_admob("release_rewarded", release, 0);
	}
	return id;
}

void FirebaseAdmobNative::release_rewarded(int64_t p_ad_id) {
	{
		std::lock_guard<std::mutex> lock(state_mutex);
		auto ad = ads.find(p_ad_id);
		if (!initialized || ad == ads.end() || ad->second.showing) {
			return;
		}
		ads.erase(ad);
	}
	Dictionary payload;
	payload["ad_id"] = p_ad_id;
	dispatch_admob("release_rewarded", payload, 0);
}

void FirebaseAdmobNative::_bind_methods() {
	using godot::D_METHOD;
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseAdmobNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("request_consent", "options"), &FirebaseAdmobNative::request_consent);
	godot::ClassDB::bind_method(D_METHOD("show_privacy_options"), &FirebaseAdmobNative::show_privacy_options);
	godot::ClassDB::bind_method(D_METHOD("reset_consent"), &FirebaseAdmobNative::reset_consent);
	godot::ClassDB::bind_method(D_METHOD("set_request_configuration", "config"), &FirebaseAdmobNative::set_request_configuration);
	godot::ClassDB::bind_method(D_METHOD("load_rewarded", "ad_unit_id"), &FirebaseAdmobNative::load_rewarded);
	godot::ClassDB::bind_method(D_METHOD("show_rewarded", "ad_id", "verification"), &FirebaseAdmobNative::show_rewarded);
	godot::ClassDB::bind_method(D_METHOD("release_rewarded", "ad_id"), &FirebaseAdmobNative::release_rewarded);
	ADD_SIGNAL(godot::MethodInfo("ad_event", godot::PropertyInfo(Variant::INT, "ad_id"), godot::PropertyInfo(Variant::STRING, "event")));
}
} // namespace godot_firebase
