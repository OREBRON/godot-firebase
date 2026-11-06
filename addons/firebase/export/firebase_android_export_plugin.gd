@tool
extends EditorExportPlugin
## Adds the generic bridge and prepares game-owned Android configuration.

const Gradle := preload("res://addons/firebase/export/firebase_android_gradle.gd")
const AAR := "res://addons/firebase/bin/android/godot_firebase.aar"
const MODULES_FILE := "res://addons/firebase/bin/modules.txt"
const CONFIG_OPTION := "firebase/google_services_json"
var _export_error := ""


func _get_name() -> String:
	return "GodotFirebaseAndroid"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_export_options_overrides(_platform: EditorExportPlatform) -> Dictionary:
	# A prebuilt APK ignores the Maven and AAR hooks this SDK requires.
	return {"gradle_build/use_gradle_build": true}


func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	var options: Array[Dictionary] = [
		{"option": {"name": CONFIG_OPTION, "type": TYPE_STRING, "hint": PROPERTY_HINT_FILE, "hint_string": "*.json"}, "default_value": "res://google-services.json"},
	]
	for key: String in Gradle.METADATA:
		options.append({"option": {"name": key, "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM,
			"hint_string": "SDK Default,Granted,Denied" if key.begins_with("firebase/consent_") else "SDK Default,Enabled,Disabled"}, "default_value": 0})
	return options


func _get_export_option_warning(_platform: EditorExportPlatform, option: String) -> String:
	if option != CONFIG_OPTION:
		return ""
	return _validate_and_prepare(true)


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("android"):
		return
	_export_error = _validate_and_prepare(false)
	if not _export_error.is_empty():
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Firebase configuration", _export_error)
		push_error("Firebase: " + _export_error)
		return
	var text := FileAccess.get_file_as_string(get_option(CONFIG_OPTION))
	add_file(FirebaseAndroidConfig.PACKED_PATH, FirebaseAndroidConfig.packed_config(text, _package_name()).to_utf8_buffer(), false)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not FileAccess.file_exists(AAR):
		push_error("Firebase: Android AAR missing; build with --platforms android.")
		return PackedStringArray()
	return PackedStringArray([AAR])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return Gradle.dependencies_for(_modules(), _play_games_enabled())


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	# Godot's export-begin callback has no abort API, and plugin option warnings
	# don't invalidate a preset. A failed preparation must also fail AAPT instead
	# of shipping an app that crashes on startup because its build ID is missing.
	if not _export_error.is_empty():
		return '<meta-data android:name="godot.firebase.export_error" android:value="@string/godot_firebase_configuration_error_see_export_log" />'
	var options := {}
	for key: String in Gradle.METADATA:
		options[key] = get_option(key)
	return Gradle.manifest_for(options, _play_games_enabled())


func _modules() -> Array:
	if not FileAccess.file_exists(MODULES_FILE):
		return []
	return Array(FileAccess.get_file_as_string(MODULES_FILE).strip_edges().split(",", false))


func _play_games_enabled() -> bool:
	return _modules().has("auth") and bool(_project_setting("firebase/auth/play_games_enabled", false))


func _project_setting(key: String, fallback: Variant) -> Variant:
	if not ProjectSettings.has_setting(key):
		return fallback
	return get_export_preset().get_project_setting(key)


func _package_name() -> String:
	var project_name: String = get_export_preset().get_project_setting("application/config/name")
	return FirebaseAndroidConfig.resolve_package_name(get_option("package/unique_name"), project_name)


func _validate_and_prepare(dry_run: bool) -> String:
	if not bool(get_option("gradle_build/use_gradle_build")):
		return "Firebase requires Android Gradle Build. Enable gradle_build/use_gradle_build and install the Android build template."
	var path: String = get_option(CONFIG_OPTION)
	if not FileAccess.file_exists(path):
		return "Download google-services.json for this package from the Firebase console."
	if not FileAccess.file_exists(AAR):
		return "Firebase Android AAR missing; build with --platforms android."
	var package_name := _package_name()
	var text := FileAccess.get_file_as_string(path)
	var config := FirebaseAndroidConfig.options_for(text, package_name)
	if config.error != OK:
		return config.message
	var games_id := ""
	if _play_games_enabled():
		games_id = str(_project_setting("firebase/auth/play_games_app_id", ""))
		if games_id.is_empty() or games_id == "<null>":
			return "Set firebase/auth/play_games_app_id to the numeric Play Games project ID."
		var client: Variant = _project_setting("firebase/auth/google_web_client_id", "")
		if not client is String or client.is_empty():
			return "Play Games server authentication requires firebase/auth/google_web_client_id."
	var directory := Gradle.build_directory(get_option("gradle_build/gradle_build_directory"))
	var prepared := Gradle.prepare(directory, text, package_name, _modules(), games_id, dry_run)
	return "" if prepared.error == OK else prepared.message
