// Desktop GDExtension: register no native Firebase classes, so GDScript uses mocks.
// Only the stable initialization ABI is needed; no SDK, CRT or godot-cpp linkage.
// ABI: godot-cpp 507ed9d840c01a3c5b2a39af8bb4000bfac30bf5,
// generated gdextension_interface.h (GDExtensionInitialization).

typedef unsigned char GDExtensionBool;
typedef void *GDExtensionClassLibraryPtr;
typedef void (*GDExtensionInterfaceFunctionPtr)(void);
typedef GDExtensionInterfaceFunctionPtr (*GDExtensionInterfaceGetProcAddress)(const char *);

typedef enum {
	GDEXTENSION_INITIALIZATION_CORE,
	GDEXTENSION_INITIALIZATION_SERVERS,
	GDEXTENSION_INITIALIZATION_SCENE,
	GDEXTENSION_INITIALIZATION_EDITOR,
	GDEXTENSION_MAX_INITIALIZATION_LEVEL,
} GDExtensionInitializationLevel;

typedef struct {
	GDExtensionInitializationLevel minimum_initialization_level;
	void *userdata;
	void (*initialize)(void *, GDExtensionInitializationLevel);
	void (*deinitialize)(void *, GDExtensionInitializationLevel);
} GDExtensionInitialization;

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	(void)level;
}

#ifdef _WIN32
#define GDE_EXPORT __declspec(dllexport)
// MinGW's default DLL entry point; no C runtime initialization is needed.
int _DllMainCRTStartup(void *instance, unsigned long reason, void *reserved) {
	(void)instance;
	(void)reason;
	(void)reserved;
	return 1;
}
#else
#define GDE_EXPORT __attribute__((visibility("default")))
#endif

GDE_EXPORT GDExtensionBool godot_firebase_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	(void)get_proc_address;
	(void)library;
	if (!initialization) {
		return 0;
	}
	initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	initialization->userdata = 0;
	initialization->initialize = initialize;
	initialization->deinitialize = initialize;
	return 1;
}
