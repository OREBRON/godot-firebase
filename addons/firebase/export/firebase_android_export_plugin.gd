@tool
extends EditorExportPlugin
## Adds the shared bridge AAR, the Firebase Maven dependencies and the game's
## google-services.json to Gradle Android exports. The JSON is checked against
## the preset's package name before export and read by the autoload at runtime.

const AAR := "res://addons/firebase/bin/android/godot_firebase.aar"
const MODULES_FILE := "res://addons/firebase/bin/modules.txt"
const CONFIG_OPTION := "firebase/google_services_json"
const DEPENDENCIES := {
	"auth": "com.google.firebase:firebase-auth:24.2.0",
	"firestore": "com.google.firebase:firebase-firestore:26.6.0",
	"storage": "com.google.firebase:firebase-storage:22.0.2",
	"database": "com.google.firebase:firebase-database:22.0.2",
	"functions": "com.google.firebase:firebase-functions:22.1.1",
}


func _get_name() -> String:
	return "GodotFirebaseAndroid"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	return [
		{"option": {"name": CONFIG_OPTION, "type": TYPE_STRING, "hint": PROPERTY_HINT_FILE, "hint_string": "*.json"}, "default_value": "res://google-services.json"},
	]


func _get_export_option_warning(_platform: EditorExportPlatform, option: String) -> String:
	if option != CONFIG_OPTION:
		return ""
	var path: String = get_option(CONFIG_OPTION)
	if not FileAccess.file_exists(path):
		return "Download google-services.json for this package from the Firebase console."
	var project_name: String = get_export_preset().get_project_setting("application/config/name")
	var package_name := FirebaseAndroidConfig.resolve_package_name(get_option("package/unique_name"), project_name)
	var config := FirebaseAndroidConfig.options_for(FileAccess.get_file_as_string(path), package_name)
	return "" if config.error == OK else config.message


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("android"):
		return
	var path: String = get_option(CONFIG_OPTION)
	if FileAccess.file_exists(path):
		add_file(FirebaseAndroidConfig.PACKED_PATH, FileAccess.get_file_as_bytes(path), false)
	else:
		push_error("Firebase: %s not found; the app cannot start Firebase." % path)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not FileAccess.file_exists(AAR):
		push_error("Firebase: Android AAR missing; build with --platforms android.")
		return PackedStringArray()
	return PackedStringArray([AAR])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	var dependencies := PackedStringArray([
		"com.google.firebase:firebase-analytics:23.2.0",
		"com.google.android.gms:play-services-base:18.10.1",
	])
	if not FileAccess.file_exists(MODULES_FILE):
		return dependencies
	for module in FileAccess.get_file_as_string(MODULES_FILE).strip_edges().split(","):
		if DEPENDENCIES.has(module):
			dependencies.append(DEPENDENCIES[module])
	return dependencies
