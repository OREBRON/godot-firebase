extends FirebaseTest
## The autoload starts every module whose folder exists, with mocks on desktop
## when no native build is configured.


func _run() -> void:
	var firebase: Node = FirebaseNode.new()
	root.add_child(firebase)
	check(firebase.auth is FirebaseAuth and firebase.firestore is FirebaseFirestore, "both module APIs start")
	for module in ["auth", "firestore"]:
		check(firebase.is_available(module), "%s has a backend" % module)
		if not ClassDB.class_exists(&"FirebaseAppNative"):
			check(firebase.is_mock(module), "%s uses the mock without native" % module)
	check(not firebase.is_available("storage"), "unknown module is unavailable")

	var result: FirebaseResult = await firebase.auth.sign_in_anonymously().wait()
	check(result.ok, "auth works through the autoload")
