extends FirebaseTest


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database
	for value in [42, "root text", true, [1, {"name": "Ada"}], {"child": 1}, null]:
		var write := await db.set_value("", value).wait()
		var read := await db.get_value("").wait()
		check(write.ok and read.ok and read.value.value == value, "root preserves scalar, array, dictionary and null: %s" % str(value))
		check(read.value.exists == (value != null), "root existence follows the stored value")
	await db.set_value("", [1, {"name": "Ada"}]).wait()
	check((await db.get_value("1/name").wait()).value.value == "Ada", "array elements can be read by numeric child path")
	await db.set_value("", {"branch": {"leaf": 1}, "sibling": true}).wait()
	await db.remove_value("branch/leaf").wait()
	check(not (await db.get_value("branch").wait()).value.exists, "deleting the last child prunes its parent")
	check((await db.get_value("").wait()).value.value == {"sibling": true}, "empty parents are omitted from ancestor values")
	await db.remove_value("sibling").wait()
	check(not (await db.get_value("").wait()).value.exists, "deleting the final leaf prunes the root")
	await db.set_value("", {"empty": {}, "null": null, "kept": 1}).wait()
	check((await db.get_value("").wait()).value.value == {"kept": 1}, "empty maps and null descendants are absent")
	await db.set_value("", 7).wait()
	await db.remove_value("missing/path").wait()
	var scalar: Variant = (await db.get_value("").wait()).value.value
	check(scalar is int and scalar == 7, "removing a missing descendant preserves scalar parent")
	await db.set_value("child", 8).wait()
	check((await db.get_value("").wait()).value.value == {"child": 8}, "writing a child replaces a scalar parent")
	var observed: Array = []
	var listener := db.listen_value("", func(result: FirebaseResult): observed.append(result.value.value))
	await process_frame
	await db.set_value("", [3, 4]).wait()
	await process_frame
	db.remove_listener(listener)
	check(observed.size() == 2 and observed[1] == [3, 4], "root listener preserves array payloads")
	var stored: Variant = (await db.get_value("").wait()).value.value
	if not stored is Array:
		check(false, "snapshot array exists for copy isolation")
		return
	var copy: Array = stored
	copy[0] = 99
	check((await db.get_value("").wait()).value.value == [3, 4], "snapshot arrays cannot mutate mock storage")
