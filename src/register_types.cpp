// GDExtension entry point. SConstruct defines GODOT_FIREBASE_<MODULE> (for
// example AUTH or REMOTE_CONFIG) for the modules selected with `modules=`, or
// GODOT_FIREBASE_EDITOR_STUB for the macOS editor library without Firebase.

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#ifndef GODOT_FIREBASE_EDITOR_STUB
#include "core/firebase_app_native.h"
#include "core/firebase_module_native.h"
#endif
#ifdef GODOT_FIREBASE_AUTH
#include "auth/firebase_auth_native.h"
#endif
#ifdef GODOT_FIREBASE_FIRESTORE
#include "firestore/firebase_firestore_native.h"
#endif
#ifdef GODOT_FIREBASE_STORAGE
#include "storage/firebase_storage_native.h"
#endif
#ifdef GODOT_FIREBASE_DATABASE
#include "database/firebase_database_native.h"
#endif
#ifdef GODOT_FIREBASE_FUNCTIONS
#include "functions/firebase_functions_native.h"
#endif
#ifdef GODOT_FIREBASE_ANALYTICS
#include "analytics/firebase_analytics_native.h"
#endif
#ifdef GODOT_FIREBASE_REMOTE_CONFIG
#include "remote_config/firebase_remote_config_native.h"
#endif
#ifdef GODOT_FIREBASE_CRASHLYTICS
#include "crashlytics/firebase_crashlytics_native.h"
#endif
#ifdef GODOT_FIREBASE_ADMOB
#include "admob/firebase_admob_native.h"
#endif

using namespace godot;

namespace {

void initialize_godot_firebase([[maybe_unused]] ModuleInitializationLevel p_level) {
#ifndef GODOT_FIREBASE_EDITOR_STUB
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(godot_firebase::FirebaseAppNative);
	GDREGISTER_ABSTRACT_CLASS(godot_firebase::FirebaseModuleNative);
#ifdef GODOT_FIREBASE_AUTH
	GDREGISTER_CLASS(godot_firebase::FirebaseAuthNative);
#endif
#ifdef GODOT_FIREBASE_FIRESTORE
	GDREGISTER_CLASS(godot_firebase::FirebaseFirestoreNative);
#endif
#ifdef GODOT_FIREBASE_STORAGE
	GDREGISTER_CLASS(godot_firebase::FirebaseStorageNative);
#endif
#ifdef GODOT_FIREBASE_DATABASE
	GDREGISTER_CLASS(godot_firebase::FirebaseDatabaseNative);
#endif
#ifdef GODOT_FIREBASE_FUNCTIONS
	GDREGISTER_CLASS(godot_firebase::FirebaseFunctionsNative);
#endif
#ifdef GODOT_FIREBASE_ANALYTICS
	GDREGISTER_CLASS(godot_firebase::FirebaseAnalyticsNative);
#endif
#ifdef GODOT_FIREBASE_REMOTE_CONFIG
	GDREGISTER_CLASS(godot_firebase::FirebaseRemoteConfigNative);
#endif
#ifdef GODOT_FIREBASE_CRASHLYTICS
	GDREGISTER_CLASS(godot_firebase::FirebaseCrashlyticsNative);
#endif
#ifdef GODOT_FIREBASE_ADMOB
	GDREGISTER_CLASS(godot_firebase::FirebaseAdmobNative);
#endif
#endif
}

void uninitialize_godot_firebase([[maybe_unused]] ModuleInitializationLevel p_level) {
#ifndef GODOT_FIREBASE_EDITOR_STUB
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
#ifdef GODOT_FIREBASE_AUTH
		godot_firebase::FirebaseAuthNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_FIRESTORE
		godot_firebase::FirebaseFirestoreNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_STORAGE
		godot_firebase::FirebaseStorageNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_DATABASE
		godot_firebase::FirebaseDatabaseNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_FUNCTIONS
		godot_firebase::FirebaseFunctionsNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_ANALYTICS
		godot_firebase::FirebaseAnalyticsNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_REMOTE_CONFIG
		godot_firebase::FirebaseRemoteConfigNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_CRASHLYTICS
		godot_firebase::FirebaseCrashlyticsNative::shutdown_all();
#endif
#ifdef GODOT_FIREBASE_ADMOB
		godot_firebase::FirebaseAdmobNative::shutdown_all();
#endif
		godot_firebase::FirebaseAppNative::shutdown();
	}
#endif
}

} // namespace

extern "C" {

GDExtensionBool GDE_EXPORT godot_firebase_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_object(p_get_proc_address, p_library, r_initialization);
	init_object.register_initializer(initialize_godot_firebase);
	init_object.register_terminator(uninitialize_godot_firebase);
	init_object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
}
