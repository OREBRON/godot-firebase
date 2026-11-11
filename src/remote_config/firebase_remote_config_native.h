#pragma once

#include <atomic>
#include <functional>

#include <firebase/remote_config.h>
#include <godot_cpp/variant/dictionary.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

class FirebaseRemoteConfigNative : public FirebaseModuleNative {
	GDCLASS(FirebaseRemoteConfigNative, FirebaseModuleNative)

public:
	FirebaseRemoteConfigNative();
	~FirebaseRemoteConfigNative() override;
	static void shutdown_all();
	godot::Error initialize();
	int64_t ensure_initialized();
	int64_t set_defaults(const godot::Dictionary &p_values);
	int64_t set_settings(int64_t p_minimum_fetch_interval_ms, int64_t p_fetch_timeout_ms);
	int64_t fetch();
	int64_t activate();
	int64_t fetch_and_activate();
	int64_t get_value(const godot::String &p_key, int64_t p_value_type = godot::Variant::STRING);
	int64_t get_keys(const godot::String &p_prefix = "");
	int64_t get_info();
	int64_t start_listening();
	void stop_listening();

protected:
	static void _bind_methods();
	bool accepts_deferred_event(const godot::StringName &p_signal, int64_t p_generation) const override;

private:
	int64_t with_config(const std::function<void(firebase::remote_config::RemoteConfig *, Completion)> &p_request);
	firebase::remote_config::RemoteConfig *config = nullptr;
	firebase::remote_config::ConfigUpdateListenerRegistration listener;
	std::atomic<int64_t> listener_generation{0};
	bool listening = false;
};

} // namespace godot_firebase
