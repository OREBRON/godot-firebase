class_name FirebaseAndroidConfig
extends RefCounted
## Reads the Firebase options of one Android app from a game's
## google-services.json. The Android export plugin checks the file with it and
## packs it at PACKED_PATH; the autoload passes the options of the running
## package to the native App. The addon itself never ships a configuration.

const PACKED_PATH := "res://addons/firebase/bin/android/google-services.json"


## Matches Godot's Android get_package_name()/get_valid_basename() rules.
## `project_name` is the export preset's application/config/name, including overrides.
static func resolve_package_name(package_name: String, project_name: String) -> String:
	if not package_name.contains("$genname"):
		return package_name
	var basename := ""
	for character in project_name.to_lower():
		if basename.is_empty() and character in "0123456789":
			continue
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			basename += character
	if basename.is_empty():
		basename = "noname"
	return package_name.replace("$genname", basename)


## options_for() on the file the export plugin packed.
static func packed_options(package_name: String) -> Dictionary:
	if not FileAccess.file_exists(PACKED_PATH):
		return _failure(ERR_FILE_NOT_FOUND, "google-services.json was not exported; set the firebase/google_services_json export option")
	return options_for(FileAccess.get_file_as_string(PACKED_PATH), package_name)


## The text the export plugin packs: project_info and only the client of
## `package_name`, so the APK does not carry the project's other apps.
## `config_text` must already pass options_for().
static func packed_config(config_text: String, package_name: String) -> String:
	var config: Dictionary = JSON.parse_string(config_text)
	return JSON.stringify({"project_info": config.get("project_info"), "client": [_client_of(config, package_name)]}, "\t")


## Returns {"error": OK, "options": {app_id, api_key, project_id, storage_bucket,
## database_url, messaging_sender_id}} for the client of `package_name`, or
## {"error": <Error>, "message": <reason>}. Field names follow Firebase's
## google-services.json to XML converter.
static func options_for(config_text: String, package_name: String) -> Dictionary:
	var config: Variant = JSON.parse_string(config_text)
	if not config is Dictionary:
		return _failure(ERR_PARSE_ERROR, "google-services.json is not a JSON object")
	var client := _client_of(config, package_name)
	if client.is_empty():
		return _failure(ERR_DOES_NOT_EXIST, "google-services.json has no Android client for package %s" % package_name)
	var project: Dictionary = _dictionary(config.get("project_info"))
	var options := {
		"app_id": _string(_dictionary(client.get("client_info")).get("mobilesdk_app_id")),
		"api_key": _api_key(client),
		"project_id": _string(project.get("project_id")),
		"storage_bucket": _string(project.get("storage_bucket")),
		"database_url": _string(project.get("firebase_url")),
		"messaging_sender_id": _string(project.get("project_number")),
	}
	if options.app_id.is_empty() or options.api_key.is_empty():
		return _failure(ERR_INVALID_DATA, "client %s has no mobilesdk_app_id or api_key" % package_name)
	return {"error": OK, "options": options}


static func _client_of(config: Dictionary, package_name: String) -> Dictionary:
	var clients: Variant = config.get("client")
	if not clients is Array:
		return {}
	for client: Variant in clients:
		var info := _dictionary(_dictionary(client).get("client_info"))
		if _string(_dictionary(info.get("android_client_info")).get("package_name")) == package_name:
			return client
	return {}


static func _api_key(client: Dictionary) -> String:
	var keys: Variant = client.get("api_key")
	if not keys is Array or keys.is_empty():
		return ""
	return _string(_dictionary(keys[0]).get("current_key"))


static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _string(value: Variant) -> String:
	return value if value is String else ""


static func _failure(error: Error, message: String) -> Dictionary:
	return {"error": error, "message": message}
