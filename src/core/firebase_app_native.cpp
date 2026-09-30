#include "firebase_app_native.h"

#include <string>

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
godot::Error FirebaseAppNative::initialize_android(JNIEnv *jni_env, jobject activity, const firebase::AppOptions &p_options) {
	if (app) {
		return godot::ERR_ALREADY_IN_USE;
	}
	if (!jni_env || !activity) {
		return godot::ERR_INVALID_PARAMETER;
	}
	// The SDK aborts on an App without app ID or API key.
	if (p_options.app_id()[0] == '\0' || p_options.api_key()[0] == '\0') {
		return godot::ERR_INVALID_DATA;
	}
	app = firebase::App::Create(p_options, jni_env, activity);
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
namespace {

// Copies a Java string argument; false when it is null.
bool copy_string(JNIEnv *jni_env, jstring p_value, std::string &r_out) {
	if (!p_value) {
		return false;
	}
	const char *chars = jni_env->GetStringUTFChars(p_value, nullptr);
	if (!chars) {
		return false;
	}
	r_out = chars;
	jni_env->ReleaseStringUTFChars(p_value, chars);
	return true;
}

} // namespace

extern "C" JNIEXPORT jint JNICALL Java_org_godotengine_godotfirebase_FirebaseBridge_nativeInitialize(
		JNIEnv *jni_env, jclass, jobject activity, jstring app_id, jstring api_key, jstring project_id,
		jstring storage_bucket, jstring database_url, jstring messaging_sender_id) {
	std::string values[6];
	const jstring arguments[6] = { app_id, api_key, project_id, storage_bucket, database_url, messaging_sender_id };
	for (int i = 0; i < 6; i++) {
		if (!copy_string(jni_env, arguments[i], values[i])) {
			return godot::ERR_INVALID_PARAMETER;
		}
	}
	firebase::AppOptions options;
	options.set_app_id(values[0].c_str());
	options.set_api_key(values[1].c_str());
	options.set_project_id(values[2].c_str());
	options.set_storage_bucket(values[3].c_str());
	options.set_database_url(values[4].c_str());
	options.set_messaging_sender_id(values[5].c_str());
	return godot_firebase::FirebaseAppNative::initialize_android(jni_env, activity, options);
}
#endif
