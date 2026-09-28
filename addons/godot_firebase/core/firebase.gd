extends Node
## Autoload "Firebase". Starts the modules whose folders are present:
## `Firebase.auth` (auth/) and `Firebase.firestore` (firestore/).
## A module whose folder was removed stays null.
##
## Backend of each module:
## - its native class, when the GDExtension was built with that module;
## - its mock on desktop when native is missing or not configured;
## - none on mobile when native fails. Requests then fail with
##   FirebaseResult.ERR_UNAVAILABLE instead of silently losing data.

const ROOT := "res://addons/godot_firebase/"
const MODULES := {
	"auth": {"api": ROOT + "auth/firebase_auth.gd", "mock": ROOT + "auth/firebase_auth_mock.gd", "native": &"FirebaseAuthNative"},
	"firestore": {"api": ROOT + "firestore/firebase_firestore.gd", "mock": ROOT + "firestore/firebase_firestore_mock.gd", "native": &"FirebaseFirestoreNative"},
}
const CONFIG_SETTING := "firebase/desktop_config_path"
const DEFAULT_CONFIG_PATH := "res://google-services-desktop.json"

## FirebaseAuth, or null without the auth module.
var auth: RefCounted
## FirebaseFirestore, or null without the firestore module.
var firestore: RefCounted
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
			api = load(MODULES[module].api).new(FirebaseRequests.new(backends[module]))
		set(module, api)


func is_available(module: String) -> bool:
	return backends.get(module) != null


func is_mock(module: String) -> bool:
	return backends.get(module) is FirebaseMockModule


func _create_backends() -> Dictionary:
	var native_app := _start_native_app()
	var created := {}
	for module in MODULES:
		if ResourceLoader.exists(MODULES[module].api):
			created[module] = _create_backend(module, native_app)
	return created


func _create_backend(module: String, native_app: bool) -> Object:
	var native_class: StringName = MODULES[module].native
	if native_app and ClassDB.class_exists(native_class):
		var native: Object = ClassDB.instantiate(native_class)
		var error: int = native.initialize()
		if error == OK:
			return native
		push_warning("Firebase: %s initialize failed (%s)" % [module, error_string(error)])
	if OS.has_feature("mobile"):
		push_error("Firebase: %s unavailable; its requests will fail" % module)
		return null
	return load(MODULES[module].mock).new()


func _start_native_app() -> bool:
	if not ClassDB.class_exists(&"FirebaseAppNative"):
		return false
	var error: int = ClassDB.class_call_static(&"FirebaseAppNative", &"initialize", _desktop_config())
	if error != OK and error != ERR_ALREADY_IN_USE:
		push_warning("Firebase: app initialize failed (%s)" % error_string(error))
		return false
	return true


## iOS reads GoogleService-Info.plist from the app bundle; desktop needs JSON.
func _desktop_config() -> String:
	if OS.has_feature("mobile"):
		return ""
	var path: String = ProjectSettings.get_setting(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
