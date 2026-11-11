extends FirebaseTest

func _run() -> void:
	var path := "res://addons/firebase/crashlytics/firebase_crashlytics_mock.gd"
	check(ResourceLoader.exists(path), "Crashlytics backend installed")
	if not ResourceLoader.exists(path):
		return
	var backend: Object = load(path).new()
	var firebase := mock_firebase({"crashlytics": backend})
	var api: Object = firebase.crashlytics
	var result: FirebaseResult = await api.log_message("level entered").wait()
	check(result.ok and backend.logs == ["level entered"], "log acknowledges local call")
	for value in ["puzzle", true, 42, 1.5]:
		result = await api.set_custom_key("mode", value).wait()
		check(result.ok and backend.custom_keys.mode == value, "scalar custom key accepted")
	for value in [null, [], {}, INF, NAN]:
		result = await api.set_custom_key("mode", value).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid custom value rejected")
	result = await api.set_custom_key("", "x").wait()
	check(not result.ok, "empty custom key rejected")
	result = await api.set_custom_keys({"level": 7, &"mode": "race", "ranked": false}).wait()
	check(result.ok and backend.custom_keys == {"level": 7, "mode": "race", "ranked": false}, "custom keys set together")
	for keys in [{"score": 1, "": 1}, {"score": 1, 2: "x"}, {"score": 1, "bad": NAN}, {"score": 1, "bad": []}]:
		result = await api.set_custom_keys(keys).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT and not backend.custom_keys.has("score"), "invalid custom keys set none")
	result = await api.set_user_id("player-1").wait()
	check(result.ok and backend.user_id == "player-1", "explicit user id")
	result = await api.clear_user_id().wait()
	check(result.ok and backend.user_id.is_empty(), "clear user id")
	var stack: Array[Dictionary] = [{"function": "save_game", "file": "res://save.gd", "line": 42}]
	result = await api.record_error("SaveError", "disk unavailable", stack).wait()
	check(result.ok and backend.errors.size() == 1, "nonfatal recorded locally")
	stack[0].line = 99
	check(backend.errors[0].stack[0].line == 42, "nonfatal snapshots supplied stack")
	for frame in [{}, {"function": "f", "file": "x", "line": "3"}, {"function": "f", "file": "x", "line": -1}, {"function": "f", "file": "x", "line": 2147483648}, {"function": "f", "file": "x", "line": 1, "extra": true}]:
		var invalid_stack: Array[Dictionary] = [frame]
		result = await api.record_error("Error", "message", invalid_stack).wait()
		check(not result.ok, "malformed frame rejected")
	result = await api.record_error("", "message").wait()
	check(not result.ok, "empty error name rejected")
	backend.unsent_reports = true
	result = await api.check_unsent_reports().wait()
	check(result.ok and result.value == false, "enabled collection check always completes false")
	result = await api.set_collection_enabled(false).wait()
	check(result.ok, "collection override accepted locally")
	result = await api.is_collection_enabled().wait()
	check(result.ok and result.value == false, "collection state observed")
	result = await api.check_unsent_reports().wait()
	check(result.ok and result.value == true, "disabled collection exposes pending reports")
	result = await api.check_unsent_reports().wait()
	check(result.ok and result.value == false, "native report check is consumed once per execution")
	result = await api.send_unsent_reports().wait()
	check(result.ok and backend.send_requested, "send is local request, not server acknowledgement")
	check(backend.unsent_reports, "send request does not invent upload completion")
	result = await api.delete_unsent_reports().wait()
	check(result.ok and backend.delete_requested, "delete is local request")
	backend.previous_execution_crashed = true
	result = await api.did_crash_previous_execution().wait()
	check(result.ok and result.value == true, "previous crash observed independently")
	backend.fail_next(123, "platform failure")
	result = await api.log_message("not recorded").wait()
	check(not result.ok and result.error_code == 123 and backend.logs.size() == 1, "platform failure preserved without mutation")
