#pragma once

#include <firebase/functions.h>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Cloud Functions (callable HTTPS functions). Method names match
// addons/firebase/functions/firebase_functions_mock.gd.
class FirebaseFunctionsNative : public FirebaseModuleNative {
	GDCLASS(FirebaseFunctionsNative, FirebaseModuleNative)

public:
	FirebaseFunctionsNative();
	~FirebaseFunctionsNative() override;
	// Registry calls this before deleting the shared Firebase App.
	static void shutdown_all();

	// Uses the region of project setting FirebaseFunctions.REGION_SETTING.
	// A non-empty `p_emulator_host` ("host:port") uses the Cloud Functions emulator.
	godot::Error initialize(const godot::String &p_emulator_host = "");
	// Not named `call`: that would hide Object.call(). A non-empty `p_region`
	// calls the function in that region instead of the setting's region.
	int64_t call_function(const godot::String &p_name, const godot::Variant &p_data, const godot::String &p_region = "");

protected:
	static void _bind_methods();

private:
	// Default region instance; null before initialize() and after shutdown_all().
	firebase::functions::Functions *functions = nullptr;
	// "http://host:port" of the emulator, or empty.
	std::string emulator_origin;
};

} // namespace godot_firebase
