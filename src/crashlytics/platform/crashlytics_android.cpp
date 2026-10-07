#include "crashlytics_platform.h"
#include <godot_cpp/classes/json.hpp>
#include "../../core/android_bridge.h"

namespace godot_firebase {
godot::Error initialize_crashlytics_platform() {
	AndroidBridge jni("org.godotengine.godotfirebase.FirebaseCrashlyticsBridge");
	if (!jni.bridge) return godot::ERR_UNAVAILABLE;
	jmethodID initialize = jni.env->GetStaticMethodID(jni.bridge, "initialize", "()Z");
	if (jni.failed() || !initialize) return godot::ERR_UNAVAILABLE;
	const bool ready = jni.env->CallStaticBooleanMethod(jni.bridge, initialize);
	return jni.failed() || !ready ? godot::ERR_UNAVAILABLE : godot::OK;
}
void dispatch_crashlytics(const godot::String &operation, const godot::Dictionary &data, int64_t id) {
	AndroidBridge jni("org.godotengine.godotfirebase.FirebaseCrashlyticsBridge");
	jmethodID request = jni.bridge ? jni.env->GetStaticMethodID(jni.bridge, "request", "(Ljava/lang/String;Ljava/lang/String;J)V") : nullptr;
	if (jni.failed() || !request) {
		finish_crashlytics_request(id, Outcome::failure(kUnavailable, "FirebaseCrashlyticsBridge is missing from the Android export"));
		return;
	}
	jstring java_operation = jni.string(operation);
	jstring java_data = jni.string(godot::JSON::stringify(data));
	if (!jni.failed() && java_operation && java_data) jni.env->CallStaticVoidMethod(jni.bridge, request, java_operation, java_data, static_cast<jlong>(id));
	const bool failed = jni.failed() || !java_operation || !java_data;
	if (java_operation) jni.env->DeleteLocalRef(java_operation);
	if (java_data) jni.env->DeleteLocalRef(java_data);
	if (failed) finish_crashlytics_request(id, Outcome::failure(kUnavailable, "Android Crashlytics bridge failed"));
}
} // namespace godot_firebase

extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseCrashlyticsBridge_nativeComplete(
		JNIEnv *env, jclass, jlong id, jint code, jstring message, jboolean has_value, jboolean value) {
	using namespace godot_firebase;
	if (code == 0) {
		finish_crashlytics_request(id, Outcome::success(has_value ? godot::Variant(static_cast<bool>(value)) : godot::Variant()));
		return;
	}
	const godot::String text = java_string(env, message);
	finish_crashlytics_request(id, Outcome::failure(code, text.is_empty() ? godot::String("Crashlytics local call failed") : text));
}
