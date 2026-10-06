#include "firebase_remote_config_native.h"

#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <unordered_set>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "../core/firebase_app_native.h"

using firebase::Future;
using firebase::remote_config::ConfigInfo;
using firebase::remote_config::ConfigKeyValueVariant;
using firebase::remote_config::ConfigSettings;
using firebase::remote_config::ConfigUpdate;
using firebase::remote_config::RemoteConfig;
using firebase::remote_config::RemoteConfigError;
using firebase::remote_config::ValueInfo;
using godot::Array;
using godot::D_METHOD;
using godot::Dictionary;
using godot::PackedByteArray;
using godot::PackedStringArray;
using godot::String;
using godot::Variant;

namespace godot_firebase {
namespace {

// Adapter ownership is main-thread-only. Multiple adapters may share GetInstance().
std::unordered_set<FirebaseRemoteConfigNative *> instances;

bool valid_key(const String &p_key) {
	return !p_key.is_empty() && to_std(p_key).find('\0') == std::string::npos;
}

bool valid_value_type(int64_t p_type) {
	return p_type == Variant::BOOL || p_type == Variant::INT || p_type == Variant::FLOAT || p_type == Variant::STRING || p_type == Variant::PACKED_BYTE_ARRAY;
}

int64_t milliseconds(uint64_t p_value) {
	// Android can expose its -1 no-fetch-yet sentinel through an unsigned field.
	if (p_value == std::numeric_limits<uint64_t>::max()) {
		return 0;
	}
	return p_value > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ? std::numeric_limits<int64_t>::max() : static_cast<int64_t>(p_value);
}

Dictionary config_info(const ConfigInfo &p_info) {
	Dictionary info;
	info["last_fetch_time_ms"] = milliseconds(p_info.fetch_time);
	info["last_fetch_status"] = static_cast<int>(p_info.last_fetch_status);
	info["last_fetch_failure_reason"] = static_cast<int>(p_info.last_fetch_failure_reason);
	info["throttled_end_time_ms"] = milliseconds(p_info.throttled_end_time);
	return info;
}

String default_value(const Variant &p_value, firebase::Variant &r_value) {
	switch (p_value.get_type()) {
		case Variant::BOOL:
			r_value = firebase::Variant(static_cast<bool>(p_value));
			break;
		case Variant::INT:
			r_value = firebase::Variant(static_cast<int64_t>(p_value));
			break;
		case Variant::FLOAT: {
			const double number = p_value;
			if (!std::isfinite(number)) {
				return "Remote Config float defaults must be finite";
			}
			r_value = firebase::Variant(number);
			break;
		}
		case Variant::STRING:
			r_value = firebase::Variant(to_std(p_value));
			break;
		case Variant::PACKED_BYTE_ARRAY: {
			const PackedByteArray bytes = p_value;
			r_value = firebase::Variant::FromMutableBlob(bytes.ptr(), static_cast<size_t>(bytes.size()));
			break;
		}
		default:
			return "Remote Config defaults must be bool, int, float, String or PackedByteArray";
	}
	return String();
}

struct Defaults {
	std::vector<std::string> keys;
	std::vector<ConfigKeyValueVariant> values;
};

String listener_error(RemoteConfigError p_error) {
	switch (p_error) {
		case firebase::remote_config::kRemoteConfigErrorConfigUpdateStreamError:
			return "Remote Config update stream failed";
		case firebase::remote_config::kRemoteConfigErrorConfigUpdateMessageInvalid:
			return "Remote Config update message is invalid";
		case firebase::remote_config::kRemoteConfigErrorConfigUpdateNotFetched:
			return "Remote Config update could not be fetched";
		case firebase::remote_config::kRemoteConfigErrorConfigUpdateUnavailable:
			return "Remote Config update service is unavailable";
		default:
			return "Remote Config update failed";
	}
}

} // namespace

FirebaseRemoteConfigNative::FirebaseRemoteConfigNative() {
	instances.insert(this);
}

FirebaseRemoteConfigNative::~FirebaseRemoteConfigNative() {
	stop_listening();
	instances.erase(this);
	if (config) {
		for (FirebaseRemoteConfigNative *other : instances) {
			if (other->config == config) {
				return;
			}
		}
		delete config;
	}
}

void FirebaseRemoteConfigNative::shutdown_all() {
	std::unordered_set<RemoteConfig *> configs;
	for (FirebaseRemoteConfigNative *instance : instances) {
		instance->stop_listening();
		if (instance->config) {
			configs.insert(instance->config);
			instance->config = nullptr;
		}
	}
	for (RemoteConfig *config : configs) {
		delete config;
	}
}

godot::Error FirebaseRemoteConfigNative::initialize() {
	if (config) {
		return godot::ERR_ALREADY_IN_USE;
	}
	firebase::App *app = FirebaseAppNative::get_app();
	if (!app) {
		return godot::ERR_UNCONFIGURED;
	}
	config = RemoteConfig::GetInstance(app);
	return config ? godot::OK : godot::ERR_CANT_CREATE;
}

int64_t FirebaseRemoteConfigNative::with_config(const std::function<void(RemoteConfig *, Completion)> &p_request) {
	return start([this, &p_request](Completion done) {
		if (!config) {
			done(Outcome::failure(kUnavailable, "FirebaseRemoteConfigNative is not initialized"));
			return;
		}
		p_request(config, std::move(done));
	});
}

int64_t FirebaseRemoteConfigNative::ensure_initialized() {
	return with_config([](RemoteConfig *config, Completion done) {
		complete_when_done(config->EnsureInitialized(), std::move(done), [](const Future<ConfigInfo> &future) {
			return Variant(config_info(*future.result()));
		});
	});
}

int64_t FirebaseRemoteConfigNative::set_defaults(const Dictionary &p_values) {
	return with_config([&p_values](RemoteConfig *config, Completion done) {
		auto defaults = std::make_shared<Defaults>();
		const Array keys = p_values.keys();
		defaults->keys.reserve(static_cast<size_t>(keys.size()));
		defaults->values.reserve(static_cast<size_t>(keys.size()));
		for (int64_t i = 0; i < keys.size(); ++i) {
			if ((keys[i].get_type() != Variant::STRING && keys[i].get_type() != Variant::STRING_NAME) || !valid_key(keys[i])) {
				done(Outcome::failure(kInvalidArgument, "Remote Config default keys must be non-empty strings without NUL"));
				return;
			}
			firebase::Variant value;
			const String reason = default_value(p_values[keys[i]], value);
			if (!reason.is_empty()) {
				done(Outcome::failure(kInvalidArgument, reason));
				return;
			}
			defaults->keys.push_back(to_std(keys[i]));
			defaults->values.push_back({defaults->keys.back().c_str(), std::move(value)});
		}
		// Keep key/blob/string storage until the asynchronous operation completes.
		complete_when_done(config->SetDefaults(defaults->values.data(), defaults->values.size()), std::move(done), [defaults](const Future<void> &) { return Variant(); });
	});
}

int64_t FirebaseRemoteConfigNative::set_settings(int64_t p_minimum_fetch_interval_ms, int64_t p_fetch_timeout_ms) {
	return with_config([=](RemoteConfig *config, Completion done) {
		if (p_minimum_fetch_interval_ms < 0 || p_fetch_timeout_ms < 0 || p_fetch_timeout_ms > std::numeric_limits<int32_t>::max()) {
			done(Outcome::failure(kInvalidArgument, "Remote Config interval must be nonnegative and timeout must be 0..2147483647 milliseconds"));
			return;
		}
		ConfigSettings settings;
		settings.minimum_fetch_interval_in_milliseconds = static_cast<uint64_t>(p_minimum_fetch_interval_ms);
		settings.fetch_timeout_in_milliseconds = static_cast<uint64_t>(p_fetch_timeout_ms);
		complete_when_done(config->SetConfigSettings(settings), std::move(done));
	});
}

int64_t FirebaseRemoteConfigNative::fetch() {
	return with_config([](RemoteConfig *config, Completion done) {
		complete_when_done(config->Fetch(), std::move(done));
	});
}

int64_t FirebaseRemoteConfigNative::activate() {
	return with_config([](RemoteConfig *config, Completion done) {
		complete_when_done(config->Activate(), std::move(done), [](const Future<bool> &future) { return Variant(*future.result()); });
	});
}

int64_t FirebaseRemoteConfigNative::fetch_and_activate() {
	return with_config([](RemoteConfig *config, Completion done) {
		complete_when_done(config->FetchAndActivate(), std::move(done), [](const Future<bool> &future) { return Variant(*future.result()); });
	});
}

int64_t FirebaseRemoteConfigNative::get_value(const String &p_key, int64_t p_value_type) {
	return with_config([&p_key, p_value_type](RemoteConfig *config, Completion done) {
		if (!valid_key(p_key) || !valid_value_type(p_value_type)) {
			done(Outcome::failure(kInvalidArgument, "invalid Remote Config key or value type"));
			return;
		}
		const std::string key = to_std(p_key);
		ValueInfo info{firebase::remote_config::kValueSourceStaticValue, false};
		Variant value;
		switch (p_value_type) {
			case Variant::BOOL: value = config->GetBoolean(key.c_str(), &info); break;
			case Variant::INT: value = config->GetLong(key.c_str(), &info); break;
			case Variant::FLOAT: value = config->GetDouble(key.c_str(), &info); break;
			case Variant::STRING: value = to_godot(config->GetString(key.c_str(), &info)); break;
			case Variant::PACKED_BYTE_ARRAY: {
				const std::vector<unsigned char> bytes = config->GetData(key.c_str(), &info);
				PackedByteArray data;
				data.resize(static_cast<int64_t>(bytes.size()));
				if (!bytes.empty()) {
					memcpy(data.ptrw(), bytes.data(), bytes.size());
				}
				value = data;
				break;
			}
		}
		Dictionary result;
		result["value"] = value;
		result["source"] = static_cast<int>(info.source);
		result["conversion_successful"] = info.conversion_successful;
		done(Outcome::success(result));
	});
}

int64_t FirebaseRemoteConfigNative::get_info() {
	return with_config([](RemoteConfig *config, Completion done) {
		done(Outcome::success(config_info(config->GetInfo())));
	});
}

int64_t FirebaseRemoteConfigNative::start_listening() {
	return with_config([this](RemoteConfig *config, Completion done) {
		if (!listening) {
			const int64_t generation = ++listener_generation;
			const uint64_t object_id = get_instance_id();
			listening = true;
			listener = config->AddOnConfigUpdateListener([object_id, generation](ConfigUpdate &&update, RemoteConfigError error) {
				if (error != firebase::remote_config::kRemoteConfigErrorNone) {
					emit_deferred_checked_to(object_id, "config_update_failed", Array::make(static_cast<int>(error), listener_error(error)), generation);
					return;
				}
				PackedStringArray keys;
				for (const std::string &key : update.updated_keys) {
					keys.push_back(to_godot(key));
				}
				emit_deferred_checked_to(object_id, "config_updated", Array::make(keys), generation);
			});
		}
		done(Outcome::success());
	});
}

void FirebaseRemoteConfigNative::stop_listening() {
	++listener_generation;
	if (!listening) {
		// Never registered, or already removed (possibly by shutdown_all before App deletion).
		return;
	}
	listening = false;
	listener.Remove();
}

bool FirebaseRemoteConfigNative::accepts_deferred_event(const godot::StringName &p_signal, int64_t p_generation) const {
	return (p_signal == godot::StringName("config_updated") || p_signal == godot::StringName("config_update_failed")) && listening && listener_generation == p_generation;
}

void FirebaseRemoteConfigNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseRemoteConfigNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("ensure_initialized"), &FirebaseRemoteConfigNative::ensure_initialized);
	godot::ClassDB::bind_method(D_METHOD("set_defaults", "values"), &FirebaseRemoteConfigNative::set_defaults);
	godot::ClassDB::bind_method(D_METHOD("set_settings", "minimum_fetch_interval_ms", "fetch_timeout_ms"), &FirebaseRemoteConfigNative::set_settings);
	godot::ClassDB::bind_method(D_METHOD("fetch"), &FirebaseRemoteConfigNative::fetch);
	godot::ClassDB::bind_method(D_METHOD("activate"), &FirebaseRemoteConfigNative::activate);
	godot::ClassDB::bind_method(D_METHOD("fetch_and_activate"), &FirebaseRemoteConfigNative::fetch_and_activate);
	godot::ClassDB::bind_method(D_METHOD("get_value", "key", "value_type"), &FirebaseRemoteConfigNative::get_value, DEFVAL(Variant::STRING));
	godot::ClassDB::bind_method(D_METHOD("get_info"), &FirebaseRemoteConfigNative::get_info);
	godot::ClassDB::bind_method(D_METHOD("start_listening"), &FirebaseRemoteConfigNative::start_listening);
	godot::ClassDB::bind_method(D_METHOD("stop_listening"), &FirebaseRemoteConfigNative::stop_listening);
	ADD_SIGNAL(godot::MethodInfo("config_updated", godot::PropertyInfo(Variant::PACKED_STRING_ARRAY, "updated_keys")));
	ADD_SIGNAL(godot::MethodInfo("config_update_failed", godot::PropertyInfo(Variant::INT, "error_code"), godot::PropertyInfo(Variant::STRING, "message")));
}

} // namespace godot_firebase
