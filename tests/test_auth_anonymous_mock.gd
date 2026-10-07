extends FirebaseTest
## Anonymous sign-in follows the SDK: a signed-in anonymous user is returned
## again; nobody or another user gets a new anonymous user.

var states: Array[Dictionary] = []


func _run() -> void:
	var firebase := mock_firebase()
	var auth: FirebaseAuth = firebase.auth
	await auth.state_changed
	auth.state_changed.connect(func(user: Dictionary): states.append(user))

	var first := await auth.sign_in_anonymously().wait()
	await process_frame
	check(first.ok and first.value.is_anonymous and states == [first.value], "signed-out anonymous sign-in reports a new user")
	var again := await auth.sign_in_anonymously().wait()
	await process_frame
	check(again.ok and again.value == first.value, "signed-in anonymous user is returned again")
	check(auth.current_user() == first.value and states.size() == 1, "returning the anonymous user reports no state change")

	var google := await auth.sign_in_with_google().wait()
	var replaced := await auth.sign_in_anonymously().wait()
	await process_frame
	check(replaced.ok and replaced.value.is_anonymous and replaced.value.uid not in [first.value.uid, google.value.uid], "provider user is replaced by a new anonymous user")
	check(states.slice(1) == [google.value, replaced.value], "replacing a provider user reports only the new user")

	auth.sign_out()
	var restored := await auth.sign_in_with_google().wait()
	check(restored.ok and restored.value.uid == google.value.uid, "replaced provider account can sign in again")
	auth.sign_out()
	var fresh := await auth.sign_in_anonymously().wait()
	check(fresh.ok and fresh.value.uid not in [first.value.uid, replaced.value.uid], "signed-out anonymous sign-in creates another user")
