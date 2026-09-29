extends FirebaseTest

var states: Array[Dictionary] = []


func _run() -> void:
	var firebase := mock_firebase()
	var auth: FirebaseAuth = firebase.auth
	auth.state_changed.connect(func(user: Dictionary): states.append(user))
	check(firebase.is_available("auth") and firebase.is_mock("auth"), "mock backend is active")
	check(not auth.is_signed_in(), "starts signed out")

	var early := await auth.link_with_apple().wait()
	check(not early.ok and early.error_code == FirebaseResult.ERR_NO_USER, "link without user fails")

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
