extends FirebaseTest


func _run() -> void:
	var db: FirebaseFirestore = mock_firebase({"firestore": FirebaseFirestoreMock.new()}).firestore
	# Insert out of order so queries must compare values rather than insertion order.
	for fixture in [
		["two", [2]],
		["long", [1, 2, 3, 1]],
		["one_float", [1.0]],
		["text", ["a"]],
		["empty", []],
		["prefix", [1, 2, 3]],
		["one", [1]],
		["tail", [1, 3]],
		["null", [null]],
		["false", [false]],
		["true", [true]],
		["packed", PackedInt32Array([1, 2])],
	]:
		var result := await db.set_doc("arrays/" + fixture[0], {"v": fixture[1]}).wait()
		check(result.ok, "array fixture is accepted: " + fixture[0])

	for fixture in [
		["<", [2], ["empty", "false", "long", "null", "one", "one_float", "packed", "prefix", "tail", "true"]],
		[">", [1], ["long", "packed", "prefix", "tail", "text", "two"]],
		["==", [1], ["one", "one_float"]],
		["!=", [1], ["empty", "false", "long", "null", "packed", "prefix", "tail", "text", "true", "two"]],
		["<", [1, 2, 3], ["empty", "false", "null", "one", "one_float", "packed", "true"]],
		["<=", [1, 2, 3], ["empty", "false", "null", "one", "one_float", "packed", "prefix", "true"]],
		[">", [1, 2, 3], ["long", "tail", "text", "two"]],
		[">=", [1, 2, 3], ["long", "prefix", "tail", "text", "two"]],
		["<", [], []],
		[">", [], ["false", "long", "null", "one", "one_float", "packed", "prefix", "tail", "text", "true", "two"]],
		["==", [], ["empty"]],
	]:
		var result := await db.query("arrays", [["v", fixture[0], fixture[1]]]).wait()
		check(result.ok and result.value.map(func(doc): return doc.id) == fixture[2], "array filter %s %s returns %s" % [fixture[0], fixture[1], fixture[2]])

	var ascending := ["empty", "null", "false", "true", "one", "one_float", "packed", "prefix", "long", "tail", "two", "text"]
	var result := await db.query("arrays", [], [["v", "asc"]]).wait()
	check(result.ok and result.value.map(func(doc): return doc.id) == ascending, "ascending array order compares elements, then length, then document IDs")
	var descending := ["text", "two", "tail", "long", "prefix", "packed", "one_float", "one", "true", "false", "null", "empty"]
	result = await db.query("arrays", [], [["v", "desc"]]).wait()
	check(result.ok and result.value.map(func(doc): return doc.id) == descending, "descending array order reverses the element ordering")
	result = await db.query("arrays", [], [["v", "asc"]], 3).wait()
	check(result.ok and result.value.map(func(doc): return doc.id) == ["empty", "null", "false"], "array ordering is applied before the query limit")
