#pragma once
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include "../core/firebase_module_native.h"

namespace godot_firebase {
class FirebaseCrashlyticsNative : public FirebaseModuleNative {
	GDCLASS(FirebaseCrashlyticsNative, FirebaseModuleNative)
protected:
	static void _bind_methods();
public:
	~FirebaseCrashlyticsNative() override;
	godot::Error initialize();
	static void shutdown_all();
	int64_t log_message(const godot::String &p_message);
	int64_t set_custom_key(const godot::String &p_key, const godot::Variant &p_value);
	int64_t set_custom_keys(const godot::Dictionary &p_keys);
	int64_t set_user_id(const godot::String &p_user_id);
	int64_t clear_user_id();
	int64_t record_error(const godot::String &p_name, const godot::String &p_message, const godot::TypedArray<godot::Dictionary> &p_stack = godot::TypedArray<godot::Dictionary>());
	int64_t set_collection_enabled(bool p_enabled);
	int64_t is_collection_enabled();
	int64_t did_crash_previous_execution();
	int64_t check_unsent_reports();
	int64_t send_unsent_reports();
	int64_t delete_unsent_reports();
private:
	bool initialized = false;
	int64_t apply(const godot::String &p_operation, const godot::Dictionary &p_payload = godot::Dictionary(), const godot::String &p_reason = godot::String());
};
} // namespace godot_firebase
