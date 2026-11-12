extends FirebaseTest
## Custom token and email sign-in, reauthentication, provider list, unlink,
## profile update and reload against the auth mock.

var states: Array[Dictionary] = []


func _run() -> void:
	var firebase := mock_firebase()
	var auth: FirebaseAuth = firebase.auth
	var backend: FirebaseAuthMock = firebase.backends.auth
	await auth.state_changed

	var result := await auth.sign_in_with_custom_token("").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "custom token is required")
	result = await auth.sign_in_with_custom_token("server-token").wait()
	check(result.ok and not result.value.is_anonymous and result.value.providers.is_empty(), "custom token signs in without a provider")
	var custom_uid: String = result.value.uid
	auth.sign_out()
	result = await auth.sign_in_with_custom_token("server-token").wait()
	check(result.ok and result.value.uid == custom_uid, "same custom token returns the same account")

	result = await auth.sign_in_with_email("player@example.com", "").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "email sign-in needs a password")
	result = await auth.sign_in_with_email("player@example.com", "secret").wait()
	check(result.ok and result.value.email == "player@example.com" and result.value.providers == ["password"], "email sign-in reports the password provider")
	var uid: String = result.value.uid
	await process_frame
	auth.state_changed.connect(func(user: Dictionary): states.append(user))
	result = await auth.link_with_google().wait()
	check(result.ok and result.value.providers == ["password", "google.com"], "linked provider joins the provider list")
	result = await auth.sign_in_with_email("player@example.com", "secret").wait()
	check(result.ok and result.value.uid == uid, "the signed-in account can sign in again")

	result = await auth.reauthenticate_with_email("player@example.com", "secret").wait()
	check(result.ok and result.value == null and auth.current_user().uid == uid, "email reauthentication keeps the session")
	result = await auth.reauthenticate_with_email("other@example.com", "secret").wait()
	check(not result.ok and result.error_code == FirebaseAuthMock.USER_MISMATCH and auth.current_user().uid == uid, "another account's credential cannot reauthenticate")
	result = await auth.reauthenticate_with_email("", "secret").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "email reauthentication needs an email")
	result = await auth.reauthenticate_with_google().wait()
	check(result.ok and auth.current_user().uid == uid, "linked provider reauthenticates")
	backend.set_provider_account("google", "someone-else")
	result = await auth.reauthenticate_with_google().wait()
	check(not result.ok and result.error_code == FirebaseAuthMock.USER_MISMATCH and auth.current_user().uid == uid, "picking another Google account fails reauthentication")
	backend.set_provider_account("google", "default")
	var requests := FirebaseRequests.new(backend)
	result = await requests.send(&"reauthenticate", ["anonymous"]).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "anonymous sign-in cannot reauthenticate")

	result = await auth.unlink_provider("").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "unlink needs a provider ID")
	result = await auth.unlink_provider("apple.com").wait()
	check(not result.ok and result.error_code == FirebaseAuthMock.NO_SUCH_PROVIDER, "unlinking a provider that is not linked fails")
	result = await auth.unlink_provider("google.com").wait()
	check(result.ok and auth.current_user().providers == ["password"] and auth.current_user().uid == uid, "unlink removes the provider and keeps the account")

	result = await auth.update_profile({"nickname": "Ada"}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "unknown profile key is rejected")
	result = await auth.update_profile({"display_name": 3}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "profile values must be Strings")
	result = await auth.update_profile({"display_name": "Ada", "photo_url": "https://example.com/ada.png"}).wait()
	check(result.ok and auth.current_user().display_name == "Ada" and auth.current_user().photo_url == "https://example.com/ada.png", "profile update changes the user")
	result = await auth.update_profile({"photo_url": ""}).wait()
	check(result.ok and auth.current_user().display_name == "Ada" and auth.current_user().photo_url == "", "a key left out keeps its value; empty clears")
	result = await auth.reload_user().wait()
	check(result.ok and auth.current_user().display_name == "Ada", "reload keeps the signed-in user")
	await process_frame
	check(states.is_empty(), "link, same-account sign-in, reauthentication, unlink, profile update and reload report no state change")

	auth.sign_out()
	result = await auth.sign_in_with_google().wait()
	check(result.ok and result.value.uid != uid, "unlinked provider no longer signs in to the account")
	auth.sign_out()
	result = await auth.sign_in_with_email("player@example.com", "secret").wait()
	check(result.ok and result.value.uid == uid and result.value.display_name == "Ada", "profile is stored on the account")

	auth.sign_out()
	for task: FirebaseTask in [auth.reauthenticate_with_google(), auth.reauthenticate_with_email("player@example.com", "secret"), auth.unlink_provider("password"), auth.update_profile({}), auth.reload_user()]:
		result = await task.wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_NO_USER, "signed-out account operation fails with ERR_NO_USER")
