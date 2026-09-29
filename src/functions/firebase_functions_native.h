#pragma once

#include <firebase/functions.h>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Cloud Functions (callable HTTPS functions). Method names match
// addons/firebase/functions/firebase_functions_mock.gd.
class FirebaseFunctionsNative : public FirebaseModuleNative {
	GDCLASS(FirebaseFunctionsNative, FirebaseModuleNative)

public:
	// Uses the region of project setting FirebaseFunctions.REGION_SETTING.
	godot::Error initialize();
	// Not named `call`: that would hide Object.call().
	int64_t call_function(const godot::String &p_name, const godot::Variant &p_data);

protected:
	static void _bind_methods();

private:
	firebase::functions::Functions *functions = nullptr;
};

} // namespace godot_firebase
