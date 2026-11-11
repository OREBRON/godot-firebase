extends FirebaseTest
## Runs tests/fixtures/guard_cases.json through the GDScript validators.
## test_native_guards.py runs the same table through the native guards.


func _run() -> void:
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/guard_cases.json"))
	check(cases is Dictionary, "guard_cases.json parses")
	if not cases is Dictionary:
		return
	for kind in cases:
		for expected in [true, false]:
			for item in cases[kind][str(expected)]:
				var text: String = item.text.repeat(int(item.times)) if item is Dictionary else item
				var label := "\"%s\" * %d" % [item.text, item.times] if item is Dictionary else "\"%s\"" % text.c_escape()
				check(_result(kind, text) == expected, "%s(%s) is %s" % [kind, label, not expected])


func _result(kind: String, text: String) -> bool:
	match kind:
		"database_is_valid_key": return FirebaseDatabase.is_valid_key(text)
		"database_is_valid_path": return FirebaseDatabase.is_valid_path(text)
		"database_is_readable_path": return FirebaseDatabase.is_readable_path(text)
		"firestore_is_document_path": return FirebaseValue.is_document_path(text)
		"firestore_is_collection_path": return FirebaseValue.is_collection_path(text)
		"firestore_is_field_path": return FirebaseValue.is_field_path(text)
		"firestore_is_reserved_field_name": return FirebaseValue.is_reserved_field_name(text)
		"firestore_is_reserved_field_path": return FirebaseValue.is_reserved_field_name(text, true)
		"firestore_is_document_id": return FirebaseFirestore._is_document_id(text)
		"storage_is_file_path": return FirebaseStorage.is_file_path(text)
		"analytics_validate_name_40": return FirebaseAnalytics.validate_name(text, 40).is_empty()
		"analytics_validate_property": return FirebaseAnalytics.validate_property_name(text).is_empty()
	check(false, "unknown kind " + kind)
	return false
