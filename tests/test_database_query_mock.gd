extends FirebaseTest


func _run() -> void:
	var db: FirebaseDatabase = mock_firebase({"database": FirebaseDatabaseMock.new()}).database
	await db.set_value("scores", {
		"ada": {"score": 30, "name": "Ada"},
		"bob": {"score": 10},
		"cem": {"score": 20},
		"deniz": {"name": "no score"},
		"eda": {"score": 30},
	}).wait()
	var top: FirebaseResult = await db.get_value("scores", {order_by = "score", limit_to_last = 3}).wait()
	check(top.ok and top.value.exists and top.value.key == "scores", "a query snapshot describes the queried location")
	check(top.ok and top.value.value.keys() == ["cem", "ada", "eda"], "limit_to_last keeps the highest scores in ascending order, ties by key")
	check(top.ok and top.value.value.ada == {"name": "Ada", "score": 30}, "query children carry their whole value")
	var lowest: Dictionary = (await db.get_value("scores", {order_by = "score", limit_to_first = 2}).wait()).value
	check(lowest.value.keys() == ["deniz", "bob"], "children without the ordered child come first")
	var range_result: Dictionary = (await db.get_value("scores", {order_by = "score", start_at = 15, end_at = 30}).wait()).value
	check(range_result.value.keys() == ["cem", "ada", "eda"], "start_at and end_at include both bounds")
	var equal: Dictionary = (await db.get_value("scores", {order_by = "score", equal_to = 30}).wait()).value
	check(equal.value.keys() == ["ada", "eda"], "equal_to keeps the exact sort value")
	var none: Dictionary = (await db.get_value("scores", {order_by = "score", start_at = 100}).wait()).value
	check(not none.exists and none.value == null, "a query without matches has no value")

	await db.set_value("keys", {"b": 1, "10": 2, "9": 3, "a": 4, "-1": 5}).wait()
	var by_key: Dictionary = (await db.get_value("keys", {order_by = "$key"}).wait()).value
	check(by_key.value.keys() == ["-1", "9", "10", "a", "b"], "integer keys come first in numeric order, then String keys")
	var key_range: Dictionary = (await db.get_value("keys", {order_by = "$key", start_at = "9", end_at = "a"}).wait()).value
	check(key_range.value.keys() == ["9", "10", "a"], "$key bounds compare keys in key order")

	await db.set_value("values", {"a": "text", "b": 2, "c": true, "d": {"x": 1}, "e": false, "f": 1.5}).wait()
	var by_value: Dictionary = (await db.get_value("values", {order_by = "$value"}).wait()).value
	check(by_value.value.keys() == ["e", "c", "f", "b", "a", "d"], "values order as false, true, numbers, Strings, then maps")
	await db.set_value("list", ["c", "a", "b"]).wait()
	var list: Dictionary = (await db.get_value("list", {order_by = "$value"}).wait()).value
	check(list.value is Dictionary and list.value.keys() == ["1", "2", "0"], "a queried list arrives as an ordered Dictionary")
	await db.set_value("leaf", 5).wait()
	check((await db.get_value("leaf", {order_by = "$value"}).wait()).value.value == 5, "a bare order_by keeps a leaf")
	check(not (await db.get_value("leaf", {order_by = "$value", limit_to_first = 1}).wait()).value.exists, "a limited query of a leaf has no value")

	var events: Array = []
	var listener := db.listen_value("scores", func(result: FirebaseResult): events.append(result.value.value), {order_by = "score", limit_to_last = 2})
	await process_frame
	await db.set_value("scores/bob/score", 5).wait()
	await db.set_value("scores/cem/score", 40).wait()
	await process_frame
	db.remove_listener(listener)
	check(events.size() == 2, "a query listener ignores changes outside its result")
	check(events.size() == 2 and events[0].keys() == ["ada", "eda"] and events[1].keys() == ["eda", "cem"], "query listener snapshots arrive in query order")

	for query: Dictionary in [
		{limit_to_first = 1},
		{order_by = "score", limit = 1},
		{order_by = "score", limit_to_first = 1, limit_to_last = 1},
		{order_by = "score", equal_to = 1, start_at = 0},
		{order_by = "score", start_at = NAN},
		{order_by = "score", start_at = [1]},
		{order_by = "$key", start_at = 1},
		{order_by = "score", limit_to_first = 0},
		{order_by = "score", limit_to_first = 1.0},
		{order_by = "score", limit_to_last = 2147483648},
		{order_by = ""},
		{order_by = "a.b"},
		{order_by = "$priority"},
	]:
		var rejected: FirebaseResult = await db.get_value("scores", query).wait()
		check(not rejected.ok and rejected.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid query is rejected: %s" % str(query))
		check(db.listen_value("scores", func(_result: FirebaseResult): pass, query) == 0, "invalid query cannot be listened to: %s" % str(query))
	check(not (await db.get_value(".info/connected", {order_by = "$value"}).wait()).ok, ".info paths cannot be queried")
