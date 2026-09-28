#pragma once

#include <firebase/app.h>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/error_macros.hpp>

namespace godot_firebase {

// Owns the process-wide firebase::App that every module uses.
class FirebaseAppNative : public godot::Object {
	GDCLASS(FirebaseAppNative, godot::Object)

public:
	// iOS reads GoogleService-Info.plist and ignores `p_config_json`.
	// Desktop needs the google-services JSON content.
	static godot::Error initialize(const godot::String &p_config_json);
	// nullptr until initialize() succeeded.
	static firebase::App *get_app();
	// Deletes the App and every Auth and Firestore object created from it.
	static void shutdown();

protected:
	static void _bind_methods();
};

} // namespace godot_firebase
