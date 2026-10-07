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

	# Inequality filters order results by the filtered field, then by document ID.
	for fixture in [
		["<", [2], ["empty", "null", "false", "true", "one", "one_float", "packed", "prefix", "long", "tail"]],
		[">", [1], ["packed", "prefix", "long", "tail", "two", "text"]],
		["==", [1], ["one", "one_float"]],
		["!=", [1], ["empty", "null", "false", "true", "packed", "prefix", "long", "tail", "two", "text"]],
		["<", [1, 2, 3], ["empty", "null", "false", "true", "one", "one_float", "packed"]],
		["<=", [1, 2, 3], ["empty", "null", "false", "true", "one", "one_float", "packed", "prefix"]],
		[">", [1, 2, 3], ["long", "tail", "two", "text"]],
		[">=", [1, 2, 3], ["prefix", "long", "tail", "two", "text"]],
		["<", [], []],
		[">", [], ["null", "false", "true", "one", "one_float", "packed", "prefix", "long", "tail", "two", "text"]],
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
