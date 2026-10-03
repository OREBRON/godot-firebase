extends FirebaseTest


func _run() -> void:
	var db: FirebaseFirestore = mock_firebase({"firestore": FirebaseFirestoreMock.new()}).firestore
	var path := "increments/value"
	for fixture in [
		{"before": {"n": 5, "discard": true}, "expected": 7},
		{"before": {"n": 1.5, "discard": true}, "expected": 3.5},
		{"before": {"n": "five", "discard": true}, "expected": 2},
		{"before": {"n": null, "discard": true}, "expected": 2},
		{"before": {"discard": true}, "expected": 2},
	]:
		await db.set_doc(path, fixture.before).wait()
		var result := await db.set_doc(path, {"n": FirebaseValue.increment(2)}, false).wait()
		check(result.ok, "replacement set with increment succeeds")
		await _expect_data(db, path, {"n": fixture.expected}, "replacement increment uses the previous numeric value and removes omitted fields")

	await db.set_doc("increments/new", {"n": FirebaseValue.increment(2)}).wait()
	await _expect_data(db, "increments/new", {"n": 2}, "increment on a missing document starts at the operand")

	await db.set_doc(path, {"profile": {"n": 5, "discard": true}, "discard": true}).wait()
	await db.set_doc(path, {"profile": {"n": FirebaseValue.increment(2)}}).wait()
	await _expect_data(db, path, {"profile": {"n": 7}}, "nested replacement increment reads the previous nested value without preserving siblings")

	await db.set_doc(path, {"profile": {"n": 7, "keep": true}}).wait()
	await db.set_doc(path, {"profile": {"n": FirebaseValue.increment(2)}}, true).wait()
	await _expect_data(db, path, {"profile": {"n": 9, "keep": true}}, "merge set increment still uses the existing value and preserves siblings")
	await db.update_doc(path, {"profile.n": FirebaseValue.increment(2)}).wait()
	await _expect_data(db, path, {"profile": {"n": 11, "keep": true}}, "dotted update increment still uses the existing value and preserves siblings")
	await db.update_doc(path, {"profile": {"n": FirebaseValue.increment(2)}}).wait()
	await _expect_data(db, path, {"profile": {"n": 13}}, "map replacement update increment reads the previous nested value")

	await db.set_doc(path, {"profile": 5}).wait()
	await db.set_doc(path, {"profile": {"n": FirebaseValue.increment(2)}}).wait()
	await _expect_data(db, path, {"profile": {"n": 2}}, "a non-map parent means the nested increment field is missing")
	await db.set_doc(path, {"literal.name": 5}).wait()
	await db.set_doc(path, {"literal.name": FirebaseValue.increment(2)}).wait()
	await _expect_data(db, path, {"literal.name": 7}, "set treats dots in field names literally")

	var result := await db.batch([
		{"op": "set", "path": path, "data": {"n": 5, "discard": true}},
		{"op": "set", "path": path, "data": {"n": FirebaseValue.increment(2)}},
		{"op": "set", "path": path, "data": {"n": FirebaseValue.increment(3)}},
	]).wait()
	check(result.ok, "sequential replacement increments commit")
	await _expect_data(db, path, {"n": 10}, "each batch increment uses the preceding write exactly once")
	await db.set_doc(path, {"n": 10}).wait()
	result = await db.batch([
		{"op": "set", "path": path, "data": {"n": FirebaseValue.increment(2)}},
		{"op": "update", "path": "increments/missing", "data": {"n": 1}},
	]).wait()
	check(not result.ok and result.error_code == FirebaseFirestoreMock.NOT_FOUND, "a later failed operation rejects the increment batch")
	await _expect_data(db, path, {"n": 10}, "failed batch preserves the previous increment value")
	result = await db.batch([
		{"op": "delete", "path": path},
		{"op": "set", "path": path, "data": {"n": FirebaseValue.increment(2)}},
	]).wait()
	check(result.ok, "delete then increment set commits")
	await _expect_data(db, path, {"n": 2}, "batch deletion clears the prior increment base")


func _expect_data(db: FirebaseFirestore, path: String, expected: Dictionary, message: String) -> void:
	var result := await db.get_doc(path).wait()
	check(result.ok and result.value.exists and result.value.data == expected, "%s: expected %s, got %s" % [message, expected, result.value])
