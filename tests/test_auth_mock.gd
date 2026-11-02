extends FirebaseTest

var states: Array[Dictionary] = []
var pending_completions := 0


func _run() -> void:
	await _session_regressions()
	var firebase := mock_firebase()
	var auth: FirebaseAuth = firebase.auth
	auth.state_changed.connect(func(user: Dictionary): states.append(user))
	check(firebase.is_available("auth") and firebase.is_mock("auth"), "mock backend is active")
	check(not auth.is_signed_in(), "starts signed out")

	var early := await auth.link_with_apple().wait()
	check(not early.ok and early.error_code == FirebaseResult.ERR_NO_USER, "link without user fails")
	check(states == [{}], "startup reports the signed-out user exactly once")

	var result := await auth.sign_in_anonymously().wait()
	check(result.ok and result.value.is_anonymous, "anonymous sign-in returns anonymous user")
	var uid: String = result.value.uid
	check(auth.current_user().uid == uid, "current user is the signed-in user")

	result = await auth.link_with_game_center().wait()
	check(result.ok and result.value.uid == uid and not result.value.is_anonymous, "link keeps uid")

	result = await auth.link_with_play_games("test-code").wait()
	check(result.ok and result.value.uid == uid, "Play Games link keeps uid")
	result = await auth.sign_in_with_play_games("").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "Play Games requires an auth code")

	result = await auth.get_id_token().wait()
	check(result.ok and result.value is String and not result.value.is_empty(), "id token is a string")

	firebase.backends.auth.fail_next(17, "network")
	result = await auth.sign_in_with_apple().wait()
	check(not result.ok and result.error_code == 17 and result.error_message == "network", "backend error reaches caller")

	result = await auth.delete_account().wait()
	check(result.ok and not auth.is_signed_in(), "delete signs out")
	await process_frame
	check(states.size() >= 3 and states[-1].is_empty(), "state_changed reports sign-in and sign-out")
	result = await auth.link_with_play_games("test-code").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_NO_USER, "Play Games link requires a user")
	result = await auth.sign_in_with_play_games("test-code").wait()
	check(result.ok and not result.value.is_anonymous, "Play Games sign-in succeeds")

	firebase.setup({"auth": null})
	check(not firebase.is_available("auth"), "backend can be missing")
	check(firebase.firestore == null, "module left out of setup stays null")
	result = await firebase.auth.sign_in_anonymously().wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_UNAVAILABLE, "missing backend fails requests")
	check(firebase.auth.current_user().is_empty(), "missing backend has no user")


func _session_regressions() -> void:
	var firebase := mock_firebase()
	var auth: FirebaseAuth = firebase.auth
	var backend = firebase.backends.auth
	var startup: Dictionary = await auth.state_changed
	check(startup.is_empty(), "awaiting state_changed at boot receives the restored user")
	var result := await auth.get_id_token().wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_NO_USER, "signed-out token fails")
	result = await auth.delete_account().wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_NO_USER, "signed-out delete fails")
	result = await auth.revoke_apple_token().wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_NO_USER, "signed-out Apple revocation fails")
	result = await auth.sign_in_with_apple().wait()
	var apple_uid: String = result.value.uid
	auth.sign_out()
	result = await auth.sign_in_with_apple().wait()
	check(result.value.uid == apple_uid, "provider relogin restores account uid")
	backend.fail_next(FirebaseResult.ERR_CANCELLED, "Apple sheet cancelled")
	result = await auth.revoke_apple_token().wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_CANCELLED, "cancelled Apple sheet fails revocation")
	result = await auth.revoke_apple_token().wait()
	check(result.ok and result.value == true and auth.current_user().uid == apple_uid, "Apple account revokes its tokens and stays signed in")
	auth.sign_out()
	result = await auth.sign_in_anonymously().wait()
	var anonymous_uid: String = result.value.uid
	result = await auth.link_with_apple().wait()
	check(not result.ok and auth.current_user().uid == anonymous_uid, "credential collision preserves current account")
	result = await auth.link_with_google().wait()
	check(result.ok and result.value.uid == anonymous_uid, "Google link preserves anonymous uid")
	result = await auth.revoke_apple_token().wait()
	check(result.ok and result.value == false, "account without Apple has nothing to revoke")
	auth.sign_out()
	result = await auth.sign_in_with_google().wait()
	check(result.ok and result.value.uid == anonymous_uid, "Google restores linked uid")
	result = await auth.link_with_play_games_platform().wait()
	check(result.ok and result.value.uid == anonymous_uid, "Play Games platform helper links")
	auth.sign_out()
	result = await auth.sign_in_with_play_games_platform().wait()
	check(result.ok and result.value.uid == anonymous_uid, "Play Games platform helper restores linked uid")
	backend.delay_next_sign_in()
	var pending := auth.link_with_game_center()
	pending.completed.connect(func(_result): pending_completions += 1)
	result = await auth.sign_in_with_apple().wait()
	check(not result.ok and result.error_code == -6, "second auth UI is busy")
	auth.sign_out()
	result = await pending.wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_CANCELLED, "sign out cancels pending link")
	result = await auth.sign_in_anonymously().wait()
	var next_uid: String = result.value.uid
	backend.complete_pending_sign_in()
	await process_frame
	check(auth.current_user().uid == next_uid and auth.current_user().is_anonymous, "late credential cannot link different uid")
	check(pending_completions == 1, "cancelled operation completes exactly once")
	backend.delay_next_sign_in()
	pending = auth.link_with_game_center()
	backend.shutdown_for_test()
	result = await pending.wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_CANCELLED, "shutdown cancels pending operation")
	backend.complete_pending_sign_in()
	await process_frame
	check(auth.current_user().uid == next_uid and auth.current_user().is_anonymous, "late credential after shutdown is ignored")
