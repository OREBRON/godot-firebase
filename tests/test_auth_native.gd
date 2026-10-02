extends FirebaseTest
## Run this in a configured mobile test export. Desktop stubs cannot exercise
## Firebase's shared Auth object; an editor skip is not native acceptance.


func _run() -> void:
	if not ClassDB.class_exists(&"FirebaseAuthNative") or not OS.has_feature("mobile"):
		print("test_auth_native.gd: native Auth lifecycle SKIPPED (requires configured mobile export)")
		return
	var firebase: Node = FirebaseNode.new()
	root.add_child(firebase)
	check(firebase.is_available("auth") and not firebase.is_mock("auth"), "configured mobile Auth backend starts")
	if not firebase.is_available("auth"):
		firebase.queue_free()
		return
	var second: Object = ClassDB.instantiate(&"FirebaseAuthNative")
	check(second.initialize() == ERR_ALREADY_IN_USE, "a second native Auth wrapper cannot share the process-wide Auth session")
	var user_before: Dictionary = firebase.backends.auth.current_user()
	second.sign_out()
	check(firebase.backends.auth.current_user() == user_before, "uninitialized wrapper sign-out cannot change the owning session")
	second = null
	firebase.queue_free()

	await process_frame
	await process_frame
	var replacement: Object = ClassDB.instantiate(&"FirebaseAuthNative")
	check(replacement.initialize() == OK, "disposing an idle owner releases the native Auth session lease")
	replacement = null
	# Pending SDK cancellation is exercised deterministically by
	# test_auth_lifecycle.py; a configured device is still needed to validate
	# real network completion and auth-state listener ordering.
