#include "firebase_app_native.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot_firebase {

namespace {
firebase::App *app = nullptr;
}

godot::Error FirebaseAppNative::initialize() {
#ifdef __ANDROID__
	return godot::ERR_UNAVAILABLE;
#else
	if (app) {
		return godot::ERR_ALREADY_IN_USE;
	}
	app = firebase::App::Create();
	return app ? godot::OK : godot::ERR_CANT_CREATE;
#endif
}

#ifdef __ANDROID__
godot::Error FirebaseAppNative::initialize_android(JNIEnv *jni_env, jobject activity) {
	if (app) {
		return godot::ERR_ALREADY_IN_USE;
	}
	if (!jni_env || !activity) {
		return godot::ERR_INVALID_PARAMETER;
	}
	app = firebase::App::Create(jni_env, activity);
	return app ? godot::OK : godot::ERR_CANT_CREATE;
}
#endif

firebase::App *FirebaseAppNative::get_app() {
	return app;
}

void FirebaseAppNative::shutdown() {
	delete app;
	app = nullptr;
}

void FirebaseAppNative::_bind_methods() {
	godot::ClassDB::bind_static_method("FirebaseAppNative", godot::D_METHOD("initialize"), &FirebaseAppNative::initialize);
}

} // namespace godot_firebase

#ifdef __ANDROID__
extern "C" JNIEXPORT jint JNICALL Java_org_godotengine_godotfirebase_FirebaseBridge_nativeInitialize(
		JNIEnv *jni_env, jclass, jobject activity) {
	return godot_firebase::FirebaseAppNative::initialize_android(jni_env, activity);
}
#endif
