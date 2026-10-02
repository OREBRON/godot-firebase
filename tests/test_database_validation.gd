extends FirebaseTest


func _run() -> void:
	var db: FirebaseDatabase = mock_firebase({"database": FirebaseDatabaseMock.new()}).database
	var deep: Variant = 1
	for i in 32:
		deep = {"a": deep}
	check(FirebaseDatabase.validate_value(deep).is_empty(), "32-level value is accepted at the root")
	deep = {"a": deep}
	var reason := FirebaseDatabase.validate_value(deep)
	check(not reason.is_empty(), "33-level value is rejected before recursion reaches SDK")
	var keys := PackedStringArray()
	for i in 32:
		keys.append("a")
	var path32 := "/".join(keys)
	check((await db.set_value(path32, 1).wait()).ok, "scalar at depth 32 is accepted")
	check(not (await db.set_value(path32, {"child": 1}).wait()).ok, "path plus value depth is bounded")
	check(not (await db.update_children(path32, {"child": 1}).wait()).ok, "update child path contributes to depth")
	for path in ["a\nb", "a\u007fb", "x".repeat(769)]:
		check(not (await db.set_value(path, 1).wait()).ok, "unsafe Firebase key is rejected")
	check(not (await db.set_value("a", NAN).wait()).ok, "nonfinite database value is rejected")
	check(not (await db.update_children("updates", {"a": 1, "a/child": 2}).wait()).ok, "overlapping update paths are rejected")
	check(not (await db.on_disconnect_update_children("updates", {"a": 1, "a/child": 2}).wait()).ok, "overlapping disconnect update paths are rejected")
	if reason.is_empty():
		return # Avoid overflowing the baseline validator while proving missing depth guard.
	var cycle: Array = []
	cycle.append(cycle)
	check(not (await db.set_value("cycle", cycle).wait()).ok, "cyclic array is rejected")
	cycle.clear()
	var map := {}
	map["self"] = map
	check(not (await db.set_value("cycle", map).wait()).ok, "cyclic dictionary is rejected")
	map.clear()
	var shared := {"x": 1}
	check((await db.set_value("shared", [shared, shared]).wait()).ok, "shared subtree is allowed")
