#pragma once
#include <godot_cpp/variant/dictionary.hpp>
#include "../core/firebase_module_native.h"

namespace godot_firebase {
class FirebaseAnalyticsNative : public FirebaseModuleNative {
	GDCLASS(FirebaseAnalyticsNative, FirebaseModuleNative)
protected:
	static void _bind_methods();
public:
	~FirebaseAnalyticsNative() override;
	godot::Error initialize();
	static void shutdown_all();
	int64_t log_event(const godot::String &p_name, const godot::Dictionary &p_parameters = godot::Dictionary());
	int64_t set_user_id(const godot::String &p_id);
	int64_t clear_user_id();
	int64_t set_user_property(const godot::String &p_name, const godot::String &p_value);
	int64_t clear_user_property(const godot::String &p_name);
	int64_t set_collection_enabled(bool p_enabled);
	int64_t set_consent(const godot::Dictionary &p_consents);
	int64_t reset_analytics_data();
private:
	bool initialized = false;
	int64_t apply(const std::function<void()> &p_action, const godot::String &p_reason = godot::String());
};
}
