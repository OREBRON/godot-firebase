extends FirebaseTest
## Written field names that begin and end with "__" abort the native Firestore SDK.
## The API must reject them for every write before any backend sees the data.


func _run() -> void:
	var backend := FirebaseFirestoreMock.new()
	var db: FirebaseFirestore = mock_firebase({"firestore": backend}).firestore
	var path := "users/u1"
	var original := {"level": 1, "profile": {"name": "Ada"}}
	check((await db.set_doc(path, original).wait()).ok, "valid document is written")

	var rejected := {
		"set": db.set_doc("users/u2", {"__x__": 1}),
		"merge set": db.set_doc(path, {"__x__": FirebaseValue.delete_field()}, true),
		"nested set": db.set_doc(path, {"profile": {"__x__": 1}}),
		"array map": db.set_doc(path, {"items": [{"__x__": 1}]}),
		"tag key at document root": db.set_doc(path, {FirebaseValue.TAG: FirebaseValue.TIMESTAMP, "seconds": 0}),
		"update key": db.update_doc(path, {"__x__": 1}),
		"update path segment": db.update_doc(path, {"profile.__": 1}),
		"update value map": db.update_doc(path, {"profile": {"__x__": 1}}),
		"batch": db.batch([{"op": "set", "path": "users/u3", "data": {"ok": true}}, {"op": "update", "path": path, "data": {"profile.___": 1}}]),
	}
	for name in rejected:
		var result: FirebaseResult = await rejected[name].wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT and result.error_message.contains("cannot begin and end with __"), "reserved name rejected before the backend: %s" % name)
	check(backend.documents.keys() == [path] and backend.documents[path] == original, "rejected writes change nothing")

	var result := await db.set_doc("users/u4", {"a.__x__": 1, "m": {"b.__y__": 2}}).wait()
	var data: Dictionary = (await db.get_doc("users/u4").wait()).value.data
	check(result.ok and data == {"a.__x__": 1, "m": {"b.__y__": 2}}, "set keys are literal names, so dotted reserved-looking parts are valid")
	result = await db.update_doc(path, {"__a.b__": 2}).wait()
	data = (await db.get_doc(path).wait()).value.data
	check(result.ok and data.get("__a") == {"b__": 2}, "update paths are checked segment by segment")

	result = await db.query("users", [["profile", "==", {"__x__": 1}]]).wait()
	check(result.ok and result.value.is_empty(), "query values may contain reserved names")
	result = await db.query("users", [["profile", "in", [{"__x__": 1}]]]).wait()
	check(result.ok and result.value.is_empty(), "'in' values may contain reserved names")
