extends FirebaseTest
## firebase/auth/mock_platform makes the auth mock fail like native on one device.

const SETTING := "firebase/auth/mock_platform"
# FirebaseAuth method -> {mock_platform: native error message}; succeeds elsewhere.
const CASES := {
	"sign_in_anonymously": {},
	"sign_in_with_google": {},
	"link_with_google": {},
	"sign_in_with_apple": {"android": "apple sign-in is not supported on Android"},
	"link_with_apple": {"android": "apple sign-in is not supported on Android"},
	"sign_in_with_game_center": {"android": "game_center sign-in is not supported on Android"},
	"link_with_game_center": {"android": "game_center sign-in is not supported on Android"},
	"sign_in_with_play_games_platform": {"ios": "play_games_platform sign-in is not supported on iOS"},
	"link_with_play_games_platform": {"ios": "play_games_platform sign-in is not supported on iOS"},
	"sign_in_with_play_games": {"ios": "Play Games sign-in requires Android"},
	"link_with_play_games": {"ios": "Play Games sign-in requires Android"},
	"reauthenticate_with_google": {},
	"reauthenticate_with_apple": {"android": "apple sign-in is not supported on Android"},
	"reauthenticate_with_game_center": {"android": "game_center sign-in is not supported on Android"},
	"reauthenticate_with_play_games_platform": {"ios": "play_games_platform sign-in is not supported on iOS"},
}

var _errors := ErrorLog.new()


class ErrorLog extends Logger:
	var messages: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(code + rationale)


func _run() -> void:
	var had_setting := ProjectSettings.has_setting(SETTING)
	var old_value: Variant = ProjectSettings.get_setting(SETTING, "")
	if had_setting:
		ProjectSettings.clear(SETTING)
	var firebase := mock_firebase({"auth": FirebaseAuthMock.new()})
	await _check_platform(firebase, "unset")
	for platform in ["", "android", "ios"]:
		ProjectSettings.set_setting(SETTING, platform)
		await _check_platform(firebase, platform)
	OS.add_logger(_errors)
	for invalid in ["windows", 1]:
		ProjectSettings.set_setting(SETTING, invalid)
		firebase.setup({"auth": FirebaseAuthMock.new()})
		var result: FirebaseResult = await firebase.auth.sign_in_with_apple().wait()
		check(result.ok, "invalid mock_platform %s falls back to every provider" % var_to_str(invalid))
	OS.remove_logger(_errors)
	check(_errors.messages.filter(func(message: String): return message.contains(SETTING)).size() == 2, "invalid mock_platform reports an error")
	ProjectSettings.clear(SETTING)
	if had_setting:
		ProjectSettings.set_setting(SETTING, old_value)


func _check_platform(firebase: Node, platform: String) -> void:
	for method: String in CASES:
		firebase.setup({"auth": FirebaseAuthMock.new()})
		var auth: FirebaseAuth = firebase.auth
		if not method.begins_with("sign_in_"):
			await auth.sign_in_anonymously().wait()
		if method.begins_with("reauthenticate_"):
			# Links where the platform allows it, so only the platform can fail reauthentication.
			await auth.call(method.replace("reauthenticate_", "link_")).wait()
		var arguments := ["server-code"] if method.ends_with("_play_games") else []
		var result: FirebaseResult = await auth.callv(method, arguments).wait()
		var error: String = CASES[method].get(platform, "")
		var label := "%s with mock_platform %s" % [method, platform]
		if error.is_empty():
			check(result.ok, label + " succeeds")
		else:
			check(not result.ok and result.error_code == FirebaseResult.ERR_UNSUPPORTED and result.error_message == error, label + " fails like native")
