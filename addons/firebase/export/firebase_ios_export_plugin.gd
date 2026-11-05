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
const GOOGLE_OPTION := "firebase/sign_in_with_google"
const STARTUP_KEYS := {
	"firebase/analytics_collection": "FIREBASE_ANALYTICS_COLLECTION_ENABLED",
	"firebase/crashlytics_collection": "FirebaseCrashlyticsCollectionEnabled",
	"firebase/consent_analytics_storage": "GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE",
	"firebase/consent_ad_storage": "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE",
	"firebase/consent_ad_user_data": "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA",
	"firebase/consent_ad_personalization": "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
}
const RESOURCES_DIR := "res://addons/firebase/bin/ios/resources"
const APPLE_ENTITLEMENT := "com.apple.developer.applesignin"
## Compiled into the export template's dummy.cpp; fixed text, never user input.
const FAIL_BUILD_CODE := "#error \"Godot Firebase iOS export failed: see the Firebase configuration error in the Godot export log.\"\n"


func _get_name() -> String:
	return "GodotFirebase"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	var options: Array[Dictionary] = [
		{"option": {"name": PLIST_OPTION, "type": TYPE_STRING, "hint": PROPERTY_HINT_FILE, "hint_string": "*.plist"}, "default_value": "res://GoogleService-Info.plist"},
		{"option": {"name": APPLE_OPTION, "type": TYPE_BOOL}, "default_value": false, "update_visibility": true},
		{"option": {"name": GAME_CENTER_OPTION, "type": TYPE_BOOL}, "default_value": false, "update_visibility": true},
		{"option": {"name": GOOGLE_OPTION, "type": TYPE_BOOL}, "default_value": false, "update_visibility": true},
	]
	for key in STARTUP_KEYS:
		options.append({"option": {"name": key, "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "SDK default,Enabled / Granted,Disabled / Denied"}, "default_value": 0, "update_visibility": true})
	return options


func _get_export_option_warning(_platform: EditorExportPlatform, option: String) -> String:
	var additional_plist := str(get_option("application/additional_plist_content"))
	if option in STARTUP_KEYS or option == "application/additional_plist_content":
		var startup := startup_plist_checked(_startup_options(), additional_plist)
		if startup.error != OK:
			return startup.message
	if option in [GOOGLE_OPTION, "application/additional_plist_content"] and get_option(GOOGLE_OPTION):
		var client: Variant = get_export_preset().get_project_setting("firebase/auth/google_ios_client_id")
		var result := google_plist(client if client is String else "", additional_plist)
		return "" if result.error == OK else result.message
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
	var google_client: Variant = null
	if get_option(GOOGLE_OPTION):
		var client: Variant = get_export_preset().get_project_setting("firebase/auth/google_ios_client_id")
		google_client = client if client is String else ""
	var plist: String = get_option(PLIST_OPTION)
	var config := export_configuration(_startup_options(), str(get_option("application/additional_plist_content")), google_client, plist)
	if config.error != OK:
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Firebase configuration", config.message)
		push_error("Firebase iOS configuration error: " + config.message)
		# Godot has no export abort API; break the generated Xcode build like Android breaks AAPT.
		add_apple_embedded_platform_cpp_code(FAIL_BUILD_CODE)
		return
	add_apple_embedded_platform_plist_content(config.content)
	add_apple_embedded_platform_bundle_file(plist)
	for bundle in DirAccess.get_directories_at(RESOURCES_DIR):
		add_apple_embedded_platform_bundle_file(RESOURCES_DIR.path_join(bundle))


func _startup_options() -> Dictionary:
	var options := {}
	for key in STARTUP_KEYS:
		options[key] = get_option(key)
	return options


## Choices apply before native SDK auto-initialization. Runtime persisted overrides
## can supersede these defaults; they are not a replacement for an app consent UI.
static func startup_plist(options: Dictionary) -> String:
	var result := ""
	for key in STARTUP_KEYS:
		var choice: Variant = options.get(key, 0)
		if choice is int and choice in [1, 2]:
			result += "<key>%s</key><%s/>\n" % [STARTUP_KEYS[key], "true" if choice == 1 else "false"]
	return result


## Everything the export adds, or the first configuration error. On error the
## export adds no Firebase content and FAIL_BUILD_CODE stops the Xcode build, so a
## rejected consent default or a missing plist cannot ship silently.
static func export_configuration(startup_options: Dictionary, additional_plist: String, google_client_id: Variant, plist_path: String) -> Dictionary:
	var startup := startup_plist_checked(startup_options, additional_plist)
	if startup.error != OK:
		return startup
	var content: String = startup.content
	if google_client_id != null:
		var google := google_plist(str(google_client_id), additional_plist)
		if google.error != OK:
			return google
		content += google.content
	if not FileAccess.file_exists(plist_path):
		return _plist_error("%s not found; download GoogleService-Info.plist from the Firebase console." % plist_path)
	return {"error": OK, "content": content}


static func startup_plist_checked(options: Dictionary, additional_plist: String) -> Dictionary:
	var parsed := _additional_plist_values(additional_plist)
	if parsed.error != OK:
		return parsed
	var remaining := options.duplicate()
	for key in STARTUP_KEYS:
		var choice: Variant = options.get(key, 0)
		var plist_key: String = STARTUP_KEYS[key]
		if not choice is int or choice not in [1, 2] or not parsed.values.has(plist_key):
			continue
		var value: Dictionary = parsed.values[plist_key]
		var expected := "true" if choice == 1 else "false"
		if value.tag != expected or not value.children.is_empty() or not value.text.strip_edges().is_empty():
			return _plist_error("%s in application/additional_plist_content conflicts with %s. Remove it or use <%s/>." % [plist_key, key, expected])
		remaining.erase(key)
	return {"error": OK, "content": startup_plist(remaining)}


static func google_plist(client_id: String, additional_plist: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]+\\.apps\\.googleusercontent\\.com$")
	if pattern.search(client_id) == null:
		return _plist_error("Set firebase/auth/google_ios_client_id to this game's iOS OAuth client ID.")
	var parsed := _additional_plist_values(additional_plist)
	if parsed.error != OK:
		return parsed
	var values: Dictionary = parsed.values
	var parts := client_id.split(".")
	parts.reverse()
	var scheme := ".".join(parts)
	var content := ""
	if values.has("GIDClientID"):
		if not _is_plist_string(values.GIDClientID, client_id):
			return _plist_error("GIDClientID in application/additional_plist_content must match firebase/auth/google_ios_client_id.")
	else:
		content = "<key>GIDClientID</key><string>%s</string>\n" % client_id.xml_escape()
	if values.has("CFBundleURLTypes"):
		# Preserve the game's array, but require the callback in an actual scheme array.
		if not _has_url_scheme(values.CFBundleURLTypes, scheme):
			return _plist_error("Add %s to CFBundleURLTypes[].CFBundleURLSchemes in application/additional_plist_content." % scheme)
	else:
		content += "<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>%s</string></array></dict></array>\n" % scheme.xml_escape()
	return {"error": OK, "content": content}


static func _has_url_scheme(url_types: Dictionary, scheme: String) -> bool:
	if url_types.tag != "array":
		return false
	for entry in url_types.children:
		var parsed := _plist_dictionary(entry)
		if parsed.error != OK:
			return false
		var schemes: Dictionary = parsed.values.get("CFBundleURLSchemes", {})
		if schemes.get("tag") != "array":
			continue
		for candidate in schemes.children:
			if _is_plist_string(candidate, scheme):
				return true
	return false


static func _is_plist_string(node: Dictionary, value: String) -> bool:
	return node.tag == "string" and node.children.is_empty() and node.text == value


## Parse a fragment with XMLParser so comments, entities and tag whitespace cannot
## impersonate keys. Keep typed XML nodes; only owned configuration values are read.
static func _additional_plist_values(fragment: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(("<plist><dict>" + fragment + "</dict></plist>").to_utf8_buffer()) != OK:
		return _plist_error("application/additional_plist_content must be a valid XML plist fragment.")
	var root := {"tag": "", "text": "", "children": []}
	var stack: Array[Dictionary] = [root]
	var result := parser.read()
	while result == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node := {"tag": parser.get_node_name(), "text": "", "children": []}
				stack.back().children.append(node)
				if not parser.is_empty():
					stack.append(node)
			XMLParser.NODE_ELEMENT_END:
				if stack.size() <= 1 or stack.back().tag != parser.get_node_name().strip_edges():
					return _plist_error("application/additional_plist_content has mismatched XML tags.")
				stack.pop_back()
			XMLParser.NODE_TEXT:
				stack.back().text += parser.get_node_data()
			XMLParser.NODE_CDATA:
				stack.back().text += parser.get_node_name()
		result = parser.read()
	if result != ERR_FILE_EOF or stack.size() != 1 or root.children.size() != 1:
		return _plist_error("application/additional_plist_content must be a valid XML plist fragment.")
	var plist: Dictionary = root.children[0]
	if plist.tag != "plist" or plist.children.size() != 1:
		return _plist_error("application/additional_plist_content must contain dictionary entries only.")
	return _plist_dictionary(plist.children[0])


static func _plist_dictionary(node: Dictionary) -> Dictionary:
	if node.tag != "dict" or node.children.size() % 2 != 0 or not node.text.strip_edges().is_empty():
		return _plist_error("application/additional_plist_content has an invalid plist dictionary.")
	var values := {}
	for index in range(0, node.children.size(), 2):
		var key: Dictionary = node.children[index]
		if key.tag != "key" or not key.children.is_empty() or values.has(key.text):
			return _plist_error("application/additional_plist_content contains an invalid or duplicate plist key: %s." % key.text)
		values[key.text] = node.children[index + 1]
	return {"error": OK, "values": values}


static func _plist_error(message: String) -> Dictionary:
	return {"error": ERR_INVALID_DATA, "message": message}
