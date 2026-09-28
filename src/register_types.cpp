// GDExtension entry point. SConstruct defines GODOT_FIREBASE_AUTH and
// GODOT_FIREBASE_FIRESTORE for the modules selected with `modules=`, or
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
#endif
}

void uninitialize_godot_firebase([[maybe_unused]] ModuleInitializationLevel p_level) {
#ifndef GODOT_FIREBASE_EDITOR_STUB
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
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
