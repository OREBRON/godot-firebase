#ifdef __ANDROID__
#include "android_bridge.h"

#include "firebase_app_native.h"

namespace godot_firebase {
AndroidBridge::AndroidBridge(const char *p_class_name) {
	auto *app = FirebaseAppNative::get_app();
	if (!app) {
		return;
	}
	vm = app->java_vm();
	activity = app->activity();
	const jint status = vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
	if (status == JNI_EDETACHED) {
		attached = vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
	} else if (status != JNI_OK) {
		env = nullptr;
	}
	if (!env) {
		return;
	}
	jclass activity_class = env->GetObjectClass(activity);
	jmethodID get_loader = env->GetMethodID(activity_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
	jobject loader = get_loader ? env->CallObjectMethod(activity, get_loader) : nullptr;
	jclass loader_class = loader ? env->GetObjectClass(loader) : nullptr;
	jmethodID load_class = loader_class ? env->GetMethodID(loader_class, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;") : nullptr;
	jstring name = env->NewStringUTF(p_class_name);
	if (load_class) {
		bridge = static_cast<jclass>(env->CallObjectMethod(loader, load_class, name));
	}
	env->DeleteLocalRef(name);
	if (loader_class) {
		env->DeleteLocalRef(loader_class);
	}
	if (loader) {
		env->DeleteLocalRef(loader);
	}
	env->DeleteLocalRef(activity_class);
	if (failed()) {
		bridge = nullptr;
	}
}

AndroidBridge::~AndroidBridge() {
	if (env && bridge) {
		env->DeleteLocalRef(bridge);
	}
	if (attached) {
		vm->DetachCurrentThread();
	}
}

bool AndroidBridge::failed() {
	if (!env || !env->ExceptionCheck()) {
		return false;
	}
	env->ExceptionClear();
	return true;
}

jstring AndroidBridge::string(const godot::String &p_value) {
	const godot::Char16String utf16 = p_value.utf16();
	return env->NewString(reinterpret_cast<const jchar *>(utf16.get_data()), utf16.length());
}

godot::String java_string(JNIEnv *p_env, jstring p_value) {
	if (!p_value) {
		return godot::String();
	}
	const jchar *chars = p_env->GetStringChars(p_value, nullptr);
	if (!chars) {
		return godot::String();
	}
	const godot::String text = godot::String::utf16(reinterpret_cast<const char16_t *>(chars), p_env->GetStringLength(p_value));
	p_env->ReleaseStringChars(p_value, chars);
	return text;
}
} // namespace godot_firebase
#endif
