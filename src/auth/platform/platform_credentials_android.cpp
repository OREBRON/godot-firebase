#include "platform_credentials.h"

#include <atomic>
#include <map>
#include <mutex>
#include <firebase/auth.h>
#include "../../core/firebase_app_native.h"
#include "../../core/outcome.h"

namespace {
std::mutex callbacks_mutex;
std::map<int64_t, godot_firebase::CredentialCallback> callbacks;
std::atomic<int64_t> next_id{0};

struct JniContext {
	JavaVM *vm = nullptr;
	JNIEnv *env = nullptr;
	jobject activity = nullptr;
	jclass bridge = nullptr;
	bool attached = false;

	JniContext() {
		auto *app = godot_firebase::FirebaseAppNative::get_app();
		if (!app) return;
		vm = app->java_vm();
		activity = app->activity();
		if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) == JNI_EDETACHED) {
			attached = vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
		}
		if (!env) return;
		// Godot's render thread is attached natively: FindClass cannot see the game's loader.
		jclass activity_class = env->GetObjectClass(activity);
		jmethodID get_loader = env->GetMethodID(activity_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
		jobject loader = get_loader ? env->CallObjectMethod(activity, get_loader) : nullptr;
		jclass loader_class = loader ? env->GetObjectClass(loader) : nullptr;
		jmethodID load_class = loader_class ? env->GetMethodID(loader_class, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;") : nullptr;
		jstring name = env->NewStringUTF("org.godotengine.godotfirebase.FirebaseAuthBridge");
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
};

std::string string_value(JNIEnv *env, jstring value) {
	if (!value) return {};
	const char *chars = env->GetStringUTFChars(value, nullptr);
	if (!chars) return {};
	std::string result(chars);
	env->ReleaseStringUTFChars(value, chars);
	return result;
}

void finish(int64_t id, godot_firebase::PlatformCredential result) {
	godot_firebase::CredentialCallback done;
	{
		std::lock_guard<std::mutex> lock(callbacks_mutex);
		auto entry = callbacks.find(id);
		if (entry == callbacks.end()) return;
		done = std::move(entry->second);
		callbacks.erase(entry);
	}
	done(std::move(result));
}
} // namespace

namespace godot_firebase {
void request_platform_credential(const std::string &provider, const PlatformCredentialOptions &options, CredentialCallback done) {
	if (provider != "google" && provider != "play_games_platform") {
		done({false, {}, kUnsupported, provider + " sign-in is not supported on Android"});
		return;
	}
	JniContext jni;
	jmethodID request = jni.bridge ? jni.env->GetStaticMethodID(jni.bridge, "request", "(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;J)V") : nullptr;
	if (!request) {
		if (jni.env && jni.env->ExceptionCheck()) jni.env->ExceptionClear();
		done({false, {}, kUnavailable, "FirebaseAuthBridge is missing from the Android export"});
		return;
	}
	const int64_t id = ++next_id;
	{
		std::lock_guard<std::mutex> lock(callbacks_mutex);
		callbacks.emplace(id, std::move(done));
	}
	jstring java_provider = jni.env->NewStringUTF(provider.c_str());
	jstring java_client = jni.env->NewStringUTF(options.google_web_client_id.c_str());
	jni.env->CallStaticVoidMethod(jni.bridge, request, jni.activity, java_provider, java_client, static_cast<jlong>(id));
	jni.env->DeleteLocalRef(java_provider);
	jni.env->DeleteLocalRef(java_client);
	if (jni.env->ExceptionCheck()) {
		jni.env->ExceptionClear();
		finish(id, {false, {}, kUnavailable, "Android provider bridge failed"});
	}
}

void clear_platform_credential_state() {
	{
		std::lock_guard<std::mutex> lock(callbacks_mutex);
		callbacks.clear();
	}
	JniContext jni;
	if (!jni.bridge) return;
	jmethodID clear = jni.env->GetStaticMethodID(jni.bridge, "clearState", "(Landroid/app/Activity;)V");
	if (clear) jni.env->CallStaticVoidMethod(jni.bridge, clear, jni.activity);
	if (jni.env->ExceptionCheck()) jni.env->ExceptionClear();
}
} // namespace godot_firebase

extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseAuthBridge_nativeComplete(
		JNIEnv *env, jclass, jlong id, jstring provider, jstring credential, jint code, jstring message) {
	godot_firebase::PlatformCredential result;
	result.error_code = code;
	result.error_message = string_value(env, message);
	if (code == 0) {
		const std::string token = string_value(env, credential);
		if (!token.empty()) {
			const std::string name = string_value(env, provider);
			if (name == "google") result.credential = firebase::auth::GoogleAuthProvider::GetCredential(token.c_str(), nullptr);
			else if (name == "play_games_platform") result.credential = firebase::auth::PlayGamesAuthProvider::GetCredential(token.c_str());
			result.ok = result.credential.is_valid();
		}
		if (!result.ok) { result.error_code = godot_firebase::kUnavailable; result.error_message = "provider credential was invalid"; }
	}
	finish(id, std::move(result));
}
