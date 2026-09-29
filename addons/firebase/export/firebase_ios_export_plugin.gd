@tool
extends EditorExportPlugin
## Adds GoogleService-Info.plist and Firebase resource bundles to iOS exports.
## The native library itself is embedded by Godot through the .gdextension file.
##
## Entitlements stay in the export preset; this plugin only warns when a
## sign-in option is enabled but its entitlement is missing.

const PLIST_OPTION := "firebase/google_service_info_plist"
const APPLE_OPTION := "firebase/sign_in_with_apple"
const GAME_CENTER_OPTION := "firebase/sign_in_with_game_center"
const RESOURCES_DIR := "res://addons/firebase/bin/ios/resources"
const APPLE_ENTITLEMENT := "com.apple.developer.applesignin"


func _get_name() -> String:
	return "GodotFirebase"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	return [
		{"option": {"name": PLIST_OPTION, "type": TYPE_STRING, "hint": PROPERTY_HINT_FILE, "hint_string": "*.plist"}, "default_value": "res://GoogleService-Info.plist"},
		{"option": {"name": APPLE_OPTION, "type": TYPE_BOOL}, "default_value": false, "update_visibility": true},
		{"option": {"name": GAME_CENTER_OPTION, "type": TYPE_BOOL}, "default_value": false, "update_visibility": true},
	]


func _get_export_option_warning(_platform: EditorExportPlatform, option: String) -> String:
	match option:
		PLIST_OPTION:
			var plist: String = get_option(PLIST_OPTION)
			if plist.get_file() != "GoogleService-Info.plist":
				return "Firebase reads the bundle file named exactly GoogleService-Info.plist."
			if not FileAccess.file_exists(plist):
				return "Download GoogleService-Info.plist from the Firebase console."
		"entitlements/additional":
			if get_option(APPLE_OPTION) and not APPLE_ENTITLEMENT in str(get_option(option)):
				return "Sign in with Apple needs <key>%s</key><array><string>Default</string></array>." % APPLE_ENTITLEMENT
		"entitlements/game_center":
			if get_option(GAME_CENTER_OPTION) and not get_option(option):
				return "Game Center sign-in needs this entitlement."
	return ""


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("ios"):
		return
	var plist: String = get_option(PLIST_OPTION)
	if FileAccess.file_exists(plist):
		add_apple_embedded_platform_bundle_file(plist)
	else:
		push_error("Firebase: %s not found; the app cannot start Firebase." % plist)
	for bundle in DirAccess.get_directories_at(RESOURCES_DIR):
		add_apple_embedded_platform_bundle_file(RESOURCES_DIR.path_join(bundle))
