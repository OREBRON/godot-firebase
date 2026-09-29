#pragma once

#include <firebase/app.h>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/error_macros.hpp>

namespace godot_firebase {

// Owns the process-wide firebase::App that every module uses.
class FirebaseAppNative : public godot::Object {
	GDCLASS(FirebaseAppNative, godot::Object)

public:
	// Reads platform Firebase resources (iOS plist / Android XML).
	static godot::Error initialize();
#ifdef __ANDROID__
	static godot::Error initialize_android(JNIEnv *jni_env, jobject activity);
#endif
	// nullptr until initialize() succeeded.
	static firebase::App *get_app();
	// Deletes the App and every Auth and Firestore object created from it.
	static void shutdown();

protected:
	static void _bind_methods();
};

} // namespace godot_firebase
