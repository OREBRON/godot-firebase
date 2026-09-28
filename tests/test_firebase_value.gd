extends FirebaseTest


func _run() -> void:
	check(FirebaseValue.is_document_path("users/u1"), "two segments is a document")
	check(FirebaseValue.is_document_path("users/u1/saves/main"), "four segments is a document")
	check(not FirebaseValue.is_document_path("users"), "one segment is not a document")
	check(not FirebaseValue.is_document_path("users//main"), "empty segment is rejected")
	check(not FirebaseValue.is_document_path(""), "empty path is rejected")
	check(FirebaseValue.is_collection_path("users/u1/saves"), "three segments is a collection")
	check(not FirebaseValue.is_collection_path("users/u1"), "two segments is not a collection")

	var stamp := FirebaseValue.timestamp(1700000000.25)
	check(stamp.seconds == 1700000000 and stamp.nanos == 250000000, "timestamp splits seconds and nanos")
	check(is_equal_approx(FirebaseValue.to_unix_seconds(stamp), 1700000000.25), "timestamp converts back")

	var valid := {
		"name": "Ada", "level": 3, "score": 1.5, "flags": [true, false], "bytes": PackedByteArray([1, 2]),
		"nested": {"at": FirebaseValue.server_timestamp()}, "coins": FirebaseValue.increment(5), "none": null,
	}
	check(FirebaseValue.validate_data(valid, false).is_empty(), "plain values, maps and sentinels are valid")
	check(not FirebaseValue.validate_data({"grid": [[1, 2]]}, false).is_empty(), "nested arrays are rejected")
	check(not FirebaseValue.validate_data({"items": [FirebaseValue.server_timestamp()]}, false).is_empty(), "sentinel inside array is rejected")
	check(not FirebaseValue.validate_data({"pos": Vector2.ONE}, false).is_empty(), "Vector2 is rejected")
	check(not FirebaseValue.validate_data({1: "x"}, false).is_empty(), "non-string key is rejected")
	check(not FirebaseValue.validate_data({"old": FirebaseValue.delete_field()}, false).is_empty(), "delete needs update or merge")
	check(FirebaseValue.validate_data({"old": FirebaseValue.delete_field()}, true).is_empty(), "delete is valid in update")
	check(not FirebaseValue.validate_data({"m": {"old": FirebaseValue.delete_field()}}, true).is_empty(), "nested delete is rejected")
	check(not FirebaseValue.validate_data({"t": {FirebaseValue.TAG: "nope"}}, false).is_empty(), "unknown tag is rejected")

	check(FirebaseValue.validate_filter_value("in", [1, 2]).is_empty(), "'in' accepts a short array")
	check(not FirebaseValue.validate_filter_value("in", []).is_empty(), "'in' rejects an empty array")
	check(not FirebaseValue.validate_filter_value("in", range(31)).is_empty(), "'in' rejects more than 30 values")
