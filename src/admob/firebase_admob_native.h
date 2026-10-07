#pragma once
#include <functional>
#include <godot_cpp/variant/dictionary.hpp>
#include "../core/firebase_module_native.h"

namespace godot_firebase {
// Google Mobile Ads rewarded ads and UMP consent through platform bridges.
// Method names match addons/firebase/admob/firebase_admob_mock.gd.
class FirebaseAdmobNative : public FirebaseModuleNative {
	GDCLASS(FirebaseAdmobNative, FirebaseModuleNative)

protected:
	static void _bind_methods();

public:
	~FirebaseAdmobNative() override;
	// Called by the extension registry before the shared App is destroyed.
	static void shutdown_all();
	// Routes a bridge event to the module that loaded `p_ad_id`.
	static void deliver_event(int64_t p_ad_id, const godot::String &p_event);

	godot::Error initialize();
	int64_t request_consent(const godot::Dictionary &p_options);
	int64_t show_privacy_options();
	int64_t reset_consent();
	int64_t set_request_configuration(const godot::Dictionary &p_config);
	int64_t load_rewarded(const godot::String &p_ad_unit_id);
	int64_t show_rewarded(int64_t p_ad_id, const godot::Dictionary &p_verification);
	void release_rewarded(int64_t p_ad_id);

private:
	// Runs `p_operation` when `p_admit` (called under the state lock) succeeds;
	// `p_finish` updates the state from the bridge outcome under the same lock.
	int64_t run(const godot::String &p_operation, const godot::Dictionary &p_payload, const std::function<Outcome()> &p_admit, std::function<void(Outcome &)> p_finish);

	bool initialized = false;
};
} // namespace godot_firebase
