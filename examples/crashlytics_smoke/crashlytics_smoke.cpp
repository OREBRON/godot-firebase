// A separate debug-only fixture. This source is never part of the SDK SConstruct.
#ifndef DEBUG_ENABLED
#error "Crashlytics smoke fixture must never be compiled into a release export"
#endif
#include <csignal>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

// Confirm this exact symbol after crash, restart, upload and console ingestion.
extern "C" __attribute__((noinline)) void godot_firebase_crashlytics_smoke_fault() {
	std::raise(SIGABRT);
}
class CrashlyticsSmokeNative : public godot::RefCounted {
	GDCLASS(CrashlyticsSmokeNative, godot::RefCounted)
protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("trigger", "confirmation"), &CrashlyticsSmokeNative::trigger);
	}
public:
	void trigger(const godot::String &confirmation) {
		if (confirmation == "CRASHLYTICS_SMOKE") godot_firebase_crashlytics_smoke_fault();
	}
};
static void initialize(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) godot::ClassDB::register_class<CrashlyticsSmokeNative>();
}
static void terminate(godot::ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT crashlytics_smoke_library_init(GDExtensionInterfaceGetProcAddress proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init(proc, library, initialization);
	init.register_initializer(initialize);
	init.register_terminator(terminate);
	init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
