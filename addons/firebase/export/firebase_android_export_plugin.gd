@tool
extends EditorExportPlugin

const AAR := "res://addons/firebase/bin/android/godot_firebase.aar"
const MODULES_FILE := "res://addons/firebase/bin/modules.txt"
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


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not FileAccess.file_exists(AAR):
		push_error("Firebase: Android AAR missing; build with --platforms android and --google-services.")
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