#include "platform_credentials.h"

#include <atomic>
#include <map>
#include <mutex>
#include <string>
#include <firebase/auth.h>
#include "../../core/android_bridge.h"
#include "../../core/outcome.h"

namespace {
// The provider is recorded here so a completion cannot pick another provider.
struct PendingRequest {
	std::string provider;
	godot_firebase::CredentialCallback done;
};
std::mutex callbacks_mutex;
std::map<int64_t, PendingRequest> callbacks;
std::atomic<int64_t> next_id{0};

std::string string_value(JNIEnv *env, jstring value) {
	if (!value) return {};
	const char *chars = env->GetStringUTFChars(value, nullptr);
	if (!chars) return {};
	std::string result(chars);
	env->ReleaseStringUTFChars(value, chars);
	return result;
}

bool take(int64_t id, PendingRequest &request) {
	std::lock_guard<std::mutex> lock(callbacks_mutex);
	auto entry = callbacks.find(id);
	if (entry == callbacks.end()) return false;
	request = std::move(entry->second);
	callbacks.erase(entry);
	return true;
}

void finish(int64_t id, godot_firebase::PlatformCredential result) {
	PendingRequest request;
	if (take(id, request)) request.done(std::move(result));
}
} // namespace

namespace godot_firebase {
void request_platform_credential(const std::string &provider, const PlatformCredentialOptions &options, CredentialCallback done) {
	if (provider != "google" && provider != "play_games_platform") {
		done({false, {}, kUnsupported, provider + " sign-in is not supported on Android"});
		return;
	}
	AndroidBridge jni("org.godotengine.godotfirebase.FirebaseAuthBridge");
	jmethodID request = jni.bridge ? jni.env->GetStaticMethodID(jni.bridge, "request", "(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;J)V") : nullptr;
	if (!request) {
		if (jni.env && jni.env->ExceptionCheck()) jni.env->ExceptionClear();
		done({false, {}, kUnavailable, "FirebaseAuthBridge is missing from the Android export"});
		return;
	}
	const int64_t id = ++next_id;
	{
		std::lock_guard<std::mutex> lock(callbacks_mutex);
		callbacks.emplace(id, PendingRequest{provider, std::move(done)});
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

void revoke_apple_token(const std::string &, Completion done) {
	done(Outcome::failure(kUnsupported, "Apple token revocation requires iOS"));
}

void clear_platform_credential_state() {
	{
		std::lock_guard<std::mutex> lock(callbacks_mutex);
		callbacks.clear();
	}
	AndroidBridge jni("org.godotengine.godotfirebase.FirebaseAuthBridge");
	if (!jni.bridge) return;
	jmethodID clear = jni.env->GetStaticMethodID(jni.bridge, "clearState", "(Landroid/app/Activity;)V");
	if (clear) jni.env->CallStaticVoidMethod(jni.bridge, clear, jni.activity);
	if (jni.env->ExceptionCheck()) jni.env->ExceptionClear();
}
} // namespace godot_firebase

extern "C" JNIEXPORT void JNICALL Java_org_godotengine_godotfirebase_FirebaseAuthBridge_nativeComplete(
		JNIEnv *env, jclass, jlong id, jstring provider, jstring credential, jint code, jstring message) {
	PendingRequest request;
	if (!take(id, request)) return;
	godot_firebase::PlatformCredential result;
	if (string_value(env, provider) != request.provider) {
		result.error_code = godot_firebase::kUnavailable;
		result.error_message = "provider response did not match the request";
		request.done(std::move(result));
		return;
	}
	result.error_code = code;
	result.error_message = string_value(env, message);
	if (code == 0) {
		const std::string token = string_value(env, credential);
		if (!token.empty()) {
			if (request.provider == "google") result.credential = firebase::auth::GoogleAuthProvider::GetCredential(token.c_str(), nullptr);
			else if (request.provider == "play_games_platform") result.credential = firebase::auth::PlayGamesAuthProvider::GetCredential(token.c_str());
			result.ok = result.credential.is_valid();
		}
		if (!result.ok) { result.error_code = godot_firebase::kUnavailable; result.error_message = "provider credential was invalid"; }
	}
	request.done(std::move(result));
}
