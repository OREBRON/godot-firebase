#pragma once
#ifdef __ANDROID__
#include <jni.h>
#include <godot_cpp/variant/string.hpp>

namespace godot_firebase {
// JNI access to one of this addon's Java bridge classes from any thread; the
// thread stays attached for the object's lifetime when it was not attached.
// Godot's render thread is attached natively, so FindClass cannot see the
// game's classes: the bridge loads through the activity's class loader.
struct AndroidBridge {
	explicit AndroidBridge(const char *p_class_name);
	~AndroidBridge();
	AndroidBridge(const AndroidBridge &) = delete;
	AndroidBridge &operator=(const AndroidBridge &) = delete;

	// Clears a pending Java exception; true when one was pending.
	bool failed();
	jstring string(const godot::String &p_value);

	JavaVM *vm = nullptr;
	JNIEnv *env = nullptr;
	jobject activity = nullptr;
	// nullptr when the class is missing from the Android export.
	jclass bridge = nullptr;

private:
	bool attached = false;
};

// Copy of a Java string; empty for null.
godot::String java_string(JNIEnv *p_env, jstring p_value);
} // namespace godot_firebase
#endif
