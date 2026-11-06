extends FirebaseTest
## FirebaseAndroidConfig picks the client of the running package from a
## google-services.json and rejects files the native App cannot start with.

const PACKAGE := "org.godotengine.firebase.test"


func _run() -> void:
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/google-services.json")
	var config := FirebaseAndroidConfig.options_for(fixture, PACKAGE)
	check(config.error == OK, "fixture client is found")
	check(config.get("options") == {
		"app_id": "1:123456789:android:0123456789abcdef", "api_key": "fake-api-key", "project_id": "firebase-test",
		"storage_bucket": "firebase-test.firebasestorage.app", "database_url": "", "messaging_sender_id": "123456789",
	}, "options follow the Firebase converter fields")

	var two_clients: Dictionary = JSON.parse_string(fixture)
	var other: Dictionary = two_clients.client[0].duplicate(true)
	other.client_info.mobilesdk_app_id = "1:123456789:android:other"
	other.client_info.android_client_info.package_name = "org.example.other"
	two_clients.client.push_front(other)
	config = FirebaseAndroidConfig.options_for(JSON.stringify(two_clients), PACKAGE)
	check(config.error == OK and config.options.app_id == "1:123456789:android:0123456789abcdef", "the matching client wins over the first one")
	config = FirebaseAndroidConfig.options_for(JSON.stringify(two_clients), "org.example.other")
	check(config.error == OK and config.options.app_id == "1:123456789:android:other", "each package gets its own client")

	_check_packed_config(JSON.stringify(two_clients))

	check(FirebaseAndroidConfig.options_for(fixture, "org.godotengine.wrong").error == ERR_DOES_NOT_EXIST, "wrong package is rejected")
	check(FirebaseAndroidConfig.options_for("not json", PACKAGE).error == ERR_PARSE_ERROR, "invalid JSON is rejected")
	check(FirebaseAndroidConfig.options_for("[]", PACKAGE).error == ERR_PARSE_ERROR, "non-object JSON is rejected")

	var no_key: Dictionary = JSON.parse_string(fixture)
	no_key.client[0].erase("api_key")
	check(FirebaseAndroidConfig.options_for(JSON.stringify(no_key), PACKAGE).error == ERR_INVALID_DATA, "missing API key is rejected")
	var no_app_id: Dictionary = JSON.parse_string(fixture)
	no_app_id.client[0].client_info.erase("mobilesdk_app_id")
	check(FirebaseAndroidConfig.options_for(JSON.stringify(no_app_id), PACKAGE).error == ERR_INVALID_DATA, "missing app ID is rejected")

	check(FirebaseAndroidConfig.packed_options(PACKAGE).error == ERR_FILE_NOT_FOUND, "missing packed config is reported")
	_check_export_packages(fixture)


## The APK carries only the exported package's client, readable by packed_options().
func _check_packed_config(two_clients: String) -> void:
	var packed := FirebaseAndroidConfig.packed_config(two_clients, PACKAGE)
	var reduced: Dictionary = JSON.parse_string(packed)
	check(reduced.size() == 2 and reduced.has("project_info") and reduced.has("client"),"packed config keeps only project_info and client")
	check(reduced.project_info == JSON.parse_string(two_clients).project_info, "packed config keeps project_info")
	check(reduced.client.size() == 1 and reduced.client[0].client_info.android_client_info.package_name == PACKAGE, "packed config keeps only the exported package's client")
	check(not packed.contains("org.example.other"), "other apps of the Firebase project are not packed")
	check(FirebaseAndroidConfig.options_for(packed, PACKAGE) == FirebaseAndroidConfig.options_for(two_clients, PACKAGE), "the runtime reader gets the same options from the packed config")
	check(FirebaseAndroidConfig.options_for(packed, "org.example.other").error == ERR_DOES_NOT_EXIST, "the packed config has no client for another package")


func _check_export_packages(fixture: String) -> void:
	for sample in [
		["com.example.$genname", "Godot Firebase", "com.example.godotfirebase"],
		["com.example.$genname", "123 My-Game_2!", "com.example.mygame_2"],
		["com.example.$genname", "École Café", "com.example.colecaf"],
		["com.example.$genname", "123 🎮!", "com.example.noname"],
		["com.example.$genname", "", "com.example.noname"],
		[PACKAGE, "Another Game", PACKAGE],
	]:
		check(FirebaseAndroidConfig.resolve_package_name(sample[0], sample[1]) == sample[2], "export package matches Godot for project %s" % sample[1])

	var config: Dictionary = JSON.parse_string(fixture)
	config.client[0].client_info.android_client_info.package_name = "com.example.godotfirebase"
	var package_name := FirebaseAndroidConfig.resolve_package_name("com.example.$genname", "Godot Firebase")
	check(FirebaseAndroidConfig.options_for(JSON.stringify(config), package_name).error == OK,
			"a client matching the generated package passes export validation")
	package_name = FirebaseAndroidConfig.resolve_package_name("com.example.$genname", "Another Game")
	check(FirebaseAndroidConfig.options_for(JSON.stringify(config), package_name).error == ERR_DOES_NOT_EXIST,
			"a client for a different generated package is still rejected")
