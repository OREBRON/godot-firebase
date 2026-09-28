extends FirebaseTest
## Round-trips values through the native Firestore converter.
## Needs a desktop debug build with the firestore module; skipped otherwise.


func _run() -> void:
	if not ClassDB.class_exists(&"FirebaseFirestoreNative"):
		print("test_native_convert.gd: skipped (no native firestore module)")
		return
	var stamp := FirebaseValue.timestamp(1700000000.5)
	var data := {
		"null": null, "bool": true, "int": 9007199254740993, "float": 1.25, "text": "çilek",
		"bytes": PackedByteArray([0, 255]), "list": [1, "a", {"deep": false}], "packed": PackedInt32Array([1, 2]),
		"map": {"inner": {"x": 1}}, "stamp": stamp,
	}
	var result: Dictionary = ClassDB.class_call_static(&"FirebaseFirestoreNative", &"debug_roundtrip", data)
	check(result.error == "", "valid data converts: %s" % result.error)
	var value: Dictionary = result.value
	for key in ["null", "bool", "int", "float", "text", "bytes", "list", "map", "stamp"]:
		check(value.get(key) == data[key], "%s round-trips (%s)" % [key, value.get(key)])
	check(value.packed == [1, 2], "packed arrays read back as Array")

	for bad in [{"grid": [[1]]}, {"v": Vector2.ONE}, {"t": {FirebaseValue.TAG: FirebaseValue.TIMESTAMP, "seconds": 0, "nanos": -1}}, {"a": [FirebaseValue.server_timestamp()]}]:
		result = ClassDB.class_call_static(&"FirebaseFirestoreNative", &"debug_roundtrip", bad)
		check(result.error != "", "rejected: %s" % str(bad))
