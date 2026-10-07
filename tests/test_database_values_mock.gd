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
	var lists := {
		"dense index map": [{"0": "a", "1": "b"}, ["a", "b"]],
		"gap": [{"0": "a", "2": "c"}, ["a", null, "c"]],
		"leading gap": [{"1": "b"}, [null, "b"]],
		"sparse index map": [{"3": "d"}, {"3": "d"}],
		"sparse array": [[null, null, null, "d"], {"3": "d"}],
		"leading zero": [{"0": "a", "01": "b"}, {"0": "a", "01": "b"}],
		"negative index": [{"0": "a", "-1": "b"}, {"-1": "b", "0": "a"}],
	}
	for name: String in lists:
		await db.set_value("list", lists[name][0]).wait()
		var delivered: Variant = (await db.get_value("list").wait()).value.value
		check(typeof(delivered) == typeof(lists[name][1]) and delivered == lists[name][1], "array rule matches the SDKs: " + name)
	await db.set_value("list", ["a", "b", "c"]).wait()
	await db.remove_value("list/1").wait()
	check((await db.get_value("list").wait()).value.value == ["a", null, "c"], "removing an element leaves a null gap")
	await db.remove_value("list/0").wait()
	var sparse: Variant = (await db.get_value("list").wait()).value.value
	check(sparse is Dictionary and sparse == {"2": "c"}, "a list that becomes too sparse arrives as a Dictionary")
	await db.set_value("order", {"b": 1, "a": {"z": 1, "y": 2}, "B": 3, "10": 4, "9": 5}).wait()
	var ordered: Variant = (await db.get_value("order").wait()).value.value
	check(ordered is Dictionary and ordered.keys() == ["10", "9", "B", "a", "b"] and ordered.a.keys() == ["y", "z"], "map keys arrive in byte order at every level")
	var listened: Array = []
	var list_listener := db.listen_value("list", func(result: FirebaseResult): listened.append(result.value.value))
	await process_frame
	await db.set_value("list", {"0": "x"}).wait()
	await process_frame
	db.remove_listener(list_listener)
	check(listened.back() is Array and listened.back() == ["x"], "listener snapshots carry delivered values")
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
