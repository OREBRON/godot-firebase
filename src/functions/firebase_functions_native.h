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
	// Not named `call`: that would hide Object.call().
	int64_t call_function(const godot::String &p_name, const godot::Variant &p_data);

protected:
	static void _bind_methods();

private:
	firebase::functions::Functions *functions = nullptr;
};

} // namespace godot_firebase
