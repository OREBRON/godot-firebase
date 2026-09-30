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
