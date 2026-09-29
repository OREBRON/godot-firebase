extends FirebaseTest

var snapshots: Array[Dictionary] = []


func _run() -> void:
	var only_firestore := mock_firebase({"firestore": FirebaseFirestoreMock.new()})
	check(only_firestore.auth == null and only_firestore.firestore != null, "firestore works without the auth module")
	var db: FirebaseFirestore = only_firestore.firestore
	var path := "users/u1/saves/main"

	var missing := await db.get_doc(path).wait()
	check(missing.ok and not missing.value.exists, "missing document reports exists = false")

	var result := await db.set_doc(path, {"level": 2, "coins": 10, "profile": {"name": "Ada", "age": 30}, "tags": PackedStringArray(["a"])}).wait()
	check(result.ok, "set succeeds")
	var doc: Dictionary = (await db.get_doc(path).wait()).value
	check(doc.exists and doc.id == "main" and doc.path == path, "snapshot has id and path")
	check(doc.data.level == 2 and doc.data.tags == ["a"], "data round-trips; packed arrays read as Array")

	await db.set_doc(path, {"profile": {"name": "Bea"}}, true).wait()
	doc = (await db.get_doc(path).wait()).value
	check(doc.data.profile == {"name": "Bea", "age": 30} and doc.data.level == 2, "merge set merges nested maps")

	await db.update_doc(path, {"coins": FirebaseValue.increment(5), "profile.age": 31, "level": FirebaseValue.delete_field(), "at": FirebaseValue.server_timestamp()}).wait()
	doc = (await db.get_doc(path).wait()).value
	check(doc.data.coins == 15, "increment adds")
	check(doc.data.profile == {"name": "Bea", "age": 31}, "dotted update changes one nested field")
	check(not doc.data.has("level"), "delete_field removes the field")
	check(FirebaseValue.tag_of(doc.data.at) == FirebaseValue.TIMESTAMP, "server timestamp reads as timestamp")

	await db.set_doc(path, {"only": true}).wait()
	doc = (await db.get_doc(path).wait()).value
	check(doc.data == {"only": true}, "set without merge replaces")

	result = await db.update_doc("users/u1/saves/none", {"a": 1}).wait()
	check(not result.ok and result.error_code == FirebaseFirestoreMock.NOT_FOUND, "update of missing document fails")

	result = await db.set_doc("users", {"a": 1}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "collection path is rejected for documents")
	result = await db.set_doc(path, {"grid": [[1]]}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid data is rejected before the backend")

	result = await db.batch([
		{"op": "set", "path": "scores/a", "data": {"score": 30, "name": "a"}},
		{"op": "set", "path": "scores/b", "data": {"score": 10, "name": "b"}},
		{"op": "set", "path": "scores/c", "data": {"score": 20, "name": "c"}},
		{"op": "set", "path": "scores/c/sub/x", "data": {"score": 99}},
		{"op": "delete", "path": path},
	]).completed
	check(result.ok, "batch commits")
	check(not (await db.get_doc(path).wait()).value.exists, "batch delete applied")
	result = await db.batch([{"op": "update", "path": "scores/a", "data": {"score": 1}}, {"op": "update", "path": "scores/zz", "data": {"score": 1}}]).wait()
	check(not result.ok and (await db.get_doc("scores/a").wait()).value.data.score == 30, "failed batch changes nothing")

	result = await db.query("scores", [["score", ">=", 15]], [["score", "desc"]]).wait()
	check(result.ok and result.value.map(func(s): return s.id) == ["a", "c"], "query filters and orders direct children")
	result = await db.query("scores", [], [["score", "asc"]], 1).wait()
	check(result.value.size() == 1 and result.value[0].id == "b", "query limit")
	result = await db.query("scores", [["name", "in", ["a", "b"]]]).wait()
	check(result.value.size() == 2, "'in' filter")
	result = await db.query("scores", [["score", "~", 1]]).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "unknown operator is rejected")

	for bad_query in [
		[[["", "==", 1]], []],
		[[["a..b", "==", 1]], []],
		[[["a/b", "==", 1]], []],
		[[[3, "==", 1]], []],
		[[["score", "==", FirebaseValue.server_timestamp()]], []],
		[[], [["", "asc"]]],
		[[], [["score", "up"]]],
	]:
		result = await db.query("scores", bad_query[0], bad_query[1]).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid query is rejected: %s" % str(bad_query))
	result = await db.query("scores", [], [], 2147483648).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "limit above int32 is rejected")
	result = await db.query("scores", [], [], 2147483647).wait()
	check(result.ok, "int32 max limit is valid")
	result = await db.query("scores", [], [], -1).wait()
	check(result.ok and result.value.size() == 3, "negative limit means no limit")

	for bad_op in [
		{"op": "set", "path": 123, "data": {"a": 1}},
		{"op": "set", "path": "scores/a", "data": {"a": 1}, "merge": "yes"},
		{"op": "set", "path": "scores/a", "data": "nope"},
		{"op": "update", "path": "scores/a", "data": {"a/b": 1}},
		{"op": 7, "path": "scores/a"},
		{"op": "set", "path": "scores/a", "data": {"t": {FirebaseValue.TAG: 5}}},
		"not a dictionary",
	]:
		result = await db.batch([bad_op]).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid batch op is rejected: %s" % str(bad_op))
	check((await db.get_doc("scores/a").wait()).value.data.score == 30, "rejected batch ops change nothing")
	result = await db.update_doc("scores/a", {"a/b": 1}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "update key with '/' is rejected")

	var id := db.listen_doc("scores/b", func(r: FirebaseResult): snapshots.append(r.value))
	await process_frame
	await db.update_doc("scores/b", {"score": 11}).wait()
	await process_frame
	db.remove_listener(id)
	await db.update_doc("scores/b", {"score": 12}).wait()
	await process_frame
	check(snapshots.size() == 2, "listener gets initial snapshot and one change, then stops")
	check(snapshots.size() == 2 and snapshots[1].data.score == 11, "listener sees the change")
	check(db.listen_doc("scores", func(_r): pass) == 0, "listening to a collection path is rejected")
