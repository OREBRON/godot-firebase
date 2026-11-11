extends FirebaseTest
## array_union() and array_remove() follow firebase-android-sdk model/mutation/ArrayTransformOperation.java.

var db: FirebaseFirestore


func _run() -> void:
	db = mock_firebase({"firestore": FirebaseFirestoreMock.new()}).firestore
	var path := "players/p1"
	await db.set_doc(path, {"tags": ["a", "b", "a"], "level": 1}).wait()

	check((await db.update_doc(path, {"tags": FirebaseValue.array_union(["b", "c", "c", &"d"])}).wait()).ok, "update with array_union succeeds")
	await _expect(path, {"tags": ["a", "b", "a", "c", "d"], "level": 1}, "array_union appends missing elements once and keeps existing duplicates")
	await db.update_doc(path, {"tags": FirebaseValue.array_remove(["a", "x"])}).wait()
	await _expect(path, {"tags": ["b", "c", "d"], "level": 1}, "array_remove removes every copy and ignores absent elements")

	await db.set_doc(path, {"scores": [1, {"k": 1}]}, true).wait()
	await db.set_doc(path, {"scores": FirebaseValue.array_union([1.0, {"k": 1}, {"k": 2}])}, true).wait()
	await _expect(path, {"tags": ["b", "c", "d"], "level": 1, "scores": [1, {"k": 1}, {"k": 2}]}, "array_union compares numbers and maps by value")
	await db.update_doc(path, {"scores": FirebaseValue.array_remove([1.0, {"k": 2}])}).wait()
	await _expect(path, {"tags": ["b", "c", "d"], "level": 1, "scores": [{"k": 1}]}, "array_remove compares numbers and maps by value")

	await db.update_doc(path, {"level": FirebaseValue.array_union(["x"]), "missing": FirebaseValue.array_union(["y"]), "gone": FirebaseValue.array_remove(["z"])}).wait()
	await _expect(path, {"tags": ["b", "c", "d"], "level": ["x"], "missing": ["y"], "gone": [], "scores": [{"k": 1}]}, "a missing or non-array field becomes the union elements or an empty array")

	await db.set_doc(path, {"profile": {"badges": ["gold"], "name": "Ada"}}).wait()
	await db.update_doc(path, {"profile.badges": FirebaseValue.array_union(["silver"])}).wait()
	await _expect(path, {"profile": {"badges": ["gold", "silver"], "name": "Ada"}}, "a dotted update path changes a nested array")
	await db.set_doc(path, {"profile": {"badges": FirebaseValue.array_union(["bronze"])}}, true).wait()
	await _expect(path, {"profile": {"badges": ["gold", "silver", "bronze"], "name": "Ada"}}, "a merge set changes a nested array and keeps siblings")

	var result := await db.batch([
		{"op": "update", "path": path, "data": {"profile.badges": FirebaseValue.array_remove(["gold"])}},
		{"op": "update", "path": path, "data": {"profile.badges": FirebaseValue.array_union(["gold"])}},
	]).wait()
	check(result.ok, "batch with array transforms commits")
	await _expect(path, {"profile": {"badges": ["silver", "bronze", "gold"], "name": "Ada"}}, "batch transforms apply in order")

	for bad in [{"tags": [FirebaseValue.array_union([1])]}, {"tags": FirebaseValue.array_union([[1]])}, {"tags": FirebaseValue.array_remove([FirebaseValue.server_timestamp()])}]:
		result = await db.update_doc(path, bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid array transform is rejected: %s" % str(bad))
	result = await db.query("players", [["tags", "array-contains", FirebaseValue.array_union([1])]]).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "array transforms cannot be query values")


func _expect(path: String, expected: Dictionary, message: String) -> void:
	var data: Dictionary = (await db.get_doc(path).wait()).value.data
	check(data == expected, "%s: expected %s, got %s" % [message, expected, data])
