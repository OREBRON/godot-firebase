extends FirebaseTest
## The test google-services.json is force-added past .gitignore; it must hold
## only these placeholder values, never a real project's config.

const FAKE := {
	"project_info": {
		"project_number": "123456789",
		"project_id": "firebase-test",
		"storage_bucket": "firebase-test.firebasestorage.app",
	},
	"client": [{
		"client_info": {
			"mobilesdk_app_id": "1:123456789:android:0123456789abcdef",
			"android_client_info": {"package_name": "org.godotengine.firebase.test"},
		},
		"api_key": [{"current_key": "fake-api-key"}],
	}],
}


func _run() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/google-services.json")
	check(JSON.parse_string(text) == FAKE, "fixture holds only the known placeholder values")
	check(not text.contains("AIza"), "fixture has no real Google API key")
