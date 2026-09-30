extends Node
## Autoload "Firebase". Starts the modules whose folders are present, for
## example `Firebase.auth` from auth/. A module whose folder was removed stays null.
## Module `x` has x/firebase_x.gd (API), x/firebase_x_mock.gd and the native
## class FirebaseXNative.
##
## Backend of each module:
## - its native class on iOS and Android, when built with that module;
## - its mock in the editor and on desktop (the macOS library is a stub);
## - none on mobile when native fails. Requests then fail with
##   FirebaseResult.ERR_UNAVAILABLE instead of silently losing data.

const ROOT := "res://addons/firebase/"
const MODULES: Array[String] = ["auth", "firestore", "storage", "database", "functions"]

## Each is the module API (FirebaseAuth, FirebaseFirestore, ...) or null
## when the module folder is missing.
var auth: RefCounted
var firestore: RefCounted
var storage: RefCounted
var database: RefCounted
var functions: RefCounted
## Module name -> backend object (null when unavailable).
var backends: Dictionary[String, Object] = {}


func _enter_tree() -> void:
	if backends.is_empty():
		setup(_create_backends())


## Wires module APIs to `module_backends` (name -> backend or null).
## Tests pass mocks, for example {"auth": FirebaseAuthMock.new()}.
func setup(module_backends: Dictionary) -> void:
	backends.assign(module_backends)
	for module in MODULES:
		var api: RefCounted = null
		if backends.has(module):
			api = load(_api_path(module)).new(FirebaseRequests.new(backends[module]))
		set(module, api)


func is_available(module: String) -> bool:
	return backends.get(module) != null


func is_mock(module: String) -> bool:
	return backends.get(module) is FirebaseMockModule


func _create_backends() -> Dictionary:
	var native_app := _start_native_app()
	var created := {}
	for module in MODULES:
		if ResourceLoader.exists(_api_path(module)):
			created[module] = _create_backend(module, native_app)
	return created


func _create_backend(module: String, native_app: bool) -> Object:
	var native_class := StringName("Firebase%sNative" % module.capitalize())
	if native_app and ClassDB.class_exists(native_class):
		var native: Object = ClassDB.instantiate(native_class)
		var error: int = native.initialize()
		if error == OK:
			return native
		push_warning("Firebase: %s initialize failed (%s)" % [module, error_string(error)])
	if OS.has_feature("mobile"):
		push_error("Firebase: %s unavailable; its requests will fail" % module)
		return null
	return load(_api_path(module).replace(".gd", "_mock.gd")).new()


func _start_native_app() -> bool:
	if not ClassDB.class_exists(&"FirebaseAppNative"):
		return false
	var error: int
	if OS.has_feature("android"):
		var runtime := Engine.get_singleton("AndroidRuntime")
		if runtime == null:
			push_error("Firebase: AndroidRuntime is unavailable")
			return false
		var wrapper := Engine.get_singleton("JavaClassWrapper")
		if wrapper == null:
			push_error("Firebase: JavaClassWrapper is unavailable")
			return false
		var bridge: Object = wrapper.wrap("org.godotengine.godotfirebase.FirebaseBridge")
		if bridge == null:
			push_error("Firebase: Android bridge is unavailable")
			return false
		var activity: Object = runtime.getActivity()
		var config := FirebaseAndroidConfig.packed_options(activity.getPackageName())
		if config.error != OK:
			push_error("Firebase: %s" % config.message)
			return false
		var options: Dictionary = config.options
		error = bridge.initialize(activity, options.app_id, options.api_key, options.project_id,
				options.storage_bucket, options.database_url, options.messaging_sender_id)
	else:
		error = ClassDB.class_call_static(&"FirebaseAppNative", &"initialize")
	if error != OK and error != ERR_ALREADY_IN_USE:
		push_warning("Firebase: app initialize failed (%s)" % error_string(error))
		return false
	return true


func _api_path(module: String) -> String:
	return ROOT + "%s/firebase_%s.gd" % [module, module]
