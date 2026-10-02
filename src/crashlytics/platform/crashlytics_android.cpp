#include "crashlytics_platform.h"
#include <godot_cpp/classes/json.hpp>
#include "../../core/firebase_app_native.h"

namespace {
struct JniContext {
	JavaVM *vm = nullptr;
	JNIEnv *env = nullptr;
	jclass bridge = nullptr;
	bool attached = false;
	JniContext() {
		auto *app = godot_firebase::FirebaseAppNative::get_app();
		if (!app) return;
		vm = app->java_vm();
		const jint status = vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
		if (status == JNI_EDETACHED) attached = vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
		else if (status != JNI_OK) env = nullptr;
		if (!env) return;
		// The Godot render thread's FindClass cannot resolve game classes.
		jobject activity = app->activity();
		jclass activity_class = env->GetObjectClass(activity);
		jmethodID get_loader = env->GetMethodID(activity_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
		jobject loader = get_loader ? env->CallObjectMethod(activity, get_loader) : nullptr;
		jclass loader_class = loader ? env->GetObjectClass(loader) : nullptr;
		jmethodID load_class = loader_class ? env->GetMethodID(loader_class, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;") : nullptr;
		jstring name = env->NewStringUTF("org.godotengine.godotfirebase.FirebaseCrashlyticsBridge");
		if (load_class) bridge = static_cast<jclass>(env->CallObjectMethod(loader, load_class, name));
		env->DeleteLocalRef(name);
		if (loader_class) env->DeleteLocalRef(loader_class);
		if (loader) env->DeleteLocalRef(loader);
		env->DeleteLocalRef(activity_class);
		if (env->ExceptionCheck()) { env->ExceptionClear(); bridge = nullptr; }
	}
	~JniContext() {
		if (env && bridge) env->DeleteLocalRef(bridge);
		if (attached) vm->DetachCurrentThread();
	}
	jstring string(const godot::String &value) {
		const godot::Char16String utf16 = value.utf16();
		return env->NewString(reinterpret_cast<const jchar *>(utf16.get_data()), utf16.length());
	}
	bool failed() {
		if (!env || !env->ExceptionCheck()) return false;
		env->ExceptionClear();
		return true;
	}
};
} // namespace
namespace godot_firebase {
godot::Error initialize_crashlytics_platform() {
	JniContext jni;
	if (!jni.bridge) return godot::ERR_UNAVAILABLE;
	jmethodID initialize = jni.env->GetStaticMethodID(jni.bridge, "initialize", "()Z");
	if (jni.failed() || !initialize) return godot::ERR_UNAVAILABLE;
	const bool ready = jni.env->CallStaticBooleanMethod(jni.bridge, initialize);
	return jni.failed() || !ready ? godot::ERR_UNAVAILABLE : godot::OK;
}
void dispatch_crashlytics(const godot::String &operation, const godot::Dictionary &data, int64_t id) {
	JniContext jni;
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
	godot::String text = "Crashlytics local call failed";
	if (message) {
		const jchar *chars = env->GetStringChars(message, nullptr);
		if (chars) { text = godot::String::utf16(reinterpret_cast<const char16_t *>(chars), env->GetStringLength(message)); env->ReleaseStringChars(message, chars); }
	}
	finish_crashlytics_request(id, Outcome::failure(code, text));
}
