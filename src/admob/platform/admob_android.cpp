#include "admob_platform.h"

#include <godot_cpp/classes/json.hpp>

#include "../../core/android_bridge.h"

namespace godot_firebase {
namespace {
const char *const kBridge = "org.godotengine.godotfirebase.FirebaseAdmobBridge";
} // namespace

godot::Error initialize_admob_platform() {
	AndroidBridge jni(kBridge);
	if (!jni.bridge) {
		return godot::ERR_UNAVAILABLE;
	}
	jmethodID initialize = jni.env->GetStaticMethodID(jni.bridge, "initialize", "(Landroid/app/Activity;)Z");
	if (jni.failed() || !initialize) {
		return godot::ERR_UNAVAILABLE;
	}
	const bool ready = jni.env->CallStaticBooleanMethod(jni.bridge, initialize, jni.activity);
	return jni.failed() || !ready ? godot::ERR_UNAVAILABLE : godot::OK;
}

void dispatch_admob(const godot::String &p_operation, const godot::Dictionary &p_payload, int64_t p_token) {
	AndroidBridge jni(kBridge);
	jmethodID request = jni.bridge ? jni.env->GetStaticMethodID(jni.bridge, "request", "(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;J)V") : nullptr;
	if (jni.failed() || !request) {
		finish_admob_request(p_token, Outcome::failure(kUnavailable, "FirebaseAdmobBridge is missing from the Android export"));
		return;
	}
	jstring operation = jni.string(p_operation);
	jstring payload = jni.string(godot::JSON::stringify(p_payload));
	if (!jni.failed() && operation && payload) {
		jni.env->CallStaticVoidMethod(jni.bridge, request, jni.activity, operation, payload, static_cast<jlong>(p_token));
	}
	const bool failed = jni.failed() || !operation || !payload;
	if (operation) {
		jni.env->DeleteLocalRef(operation);
	}
	if (payload) {
		jni.env->DeleteLocalRef(payload);
	}
	if (failed) {
		finish_admob_request(p_token, Outcome::failure(kUnavailable, "Android AdMob bridge failed"));
	}
}

void shutdown_admob_platform() {
	AndroidBridge jni(kBridge);
	jmethodID shutdown = jni.bridge ? jni.env->GetStaticMethodID(jni.bridge, "shutdown", "()V") : nullptr;
	if (!jni.failed() && shutdown) {
		jni.env->CallStaticVoidMethod(jni.bridge, shutdown);
	}
	jni.failed();
}
} // namespace godot_firebase

// The bridge calls these from the main, worker and Mobile Ads SDK threads.
extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseAdmobBridge_nativeComplete(
		JNIEnv *env, jclass, jlong token, jint code, jstring message) {
	using namespace godot_firebase;
	if (code == 0) {
		finish_admob_request(token, Outcome::success());
		return;
	}
	const godot::String text = java_string(env, message);
	finish_admob_request(token, Outcome::failure(code, text.is_empty() ? godot::String("AdMob request failed") : text));
}

extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseAdmobBridge_nativeConsent(
		JNIEnv *env, jclass, jlong token, jboolean can_request_ads, jstring consent_status, jboolean privacy_options_required) {
	using namespace godot_firebase;
	godot::Dictionary result;
	result["can_request_ads"] = static_cast<bool>(can_request_ads);
	result["consent_status"] = java_string(env, consent_status);
	result["privacy_options_required"] = static_cast<bool>(privacy_options_required);
	finish_admob_request(token, Outcome::success(result));
}

extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseAdmobBridge_nativeReward(
		JNIEnv *env, jclass, jlong token, jboolean rewarded, jstring reward_type, jint reward_amount) {
	using namespace godot_firebase;
	godot::Dictionary result;
	result["rewarded"] = static_cast<bool>(rewarded);
	result["reward_type"] = java_string(env, reward_type);
	result["reward_amount"] = static_cast<int64_t>(reward_amount);
	finish_admob_request(token, Outcome::success(result));
}

extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseAdmobBridge_nativeEvent(
		JNIEnv *env, jclass, jlong ad_id, jstring event) {
	godot_firebase::emit_admob_event(ad_id, godot_firebase::java_string(env, event));
}
