extends FirebaseTest

var snapshots: Array[Dictionary] = []


func _run() -> void:
	var firebase := mock_firebase()
	var db: FirebaseDatabase = firebase.database

	var result := await db.get_value("players/u1").wait()
	check(result.ok and not result.value.exists and result.value.value == null, "missing value does not exist")

	result = await db.set_value("players/u1", {"name": "Ada", "level": 2, "seen": FirebaseDatabase.SERVER_TIMESTAMP}).wait()
	check(result.ok, "set succeeds")
	var snapshot: Dictionary = (await db.get_value("players/u1").wait()).value
	check(snapshot.exists and snapshot.key == "u1" and snapshot.value.name == "Ada", "snapshot has key and value")
	check(snapshot.value.seen is int and snapshot.value.seen > 1700000000000, "server timestamp becomes Unix milliseconds")

	await db.update_children("players/u1", {"level": 3, "stats/wins": 1}).wait()
	snapshot = (await db.get_value("players/u1").wait()).value
	check(snapshot.value.level == 3 and snapshot.value.name == "Ada" and snapshot.value.stats == {"wins": 1}, "update changes only given children")

	result = await db.push_value("scores", {"score": 10}).wait()
	check(result.ok and result.value is String and not result.value.is_empty(), "push returns the new key")
	var key: String = result.value
	check((await db.get_value("scores/" + key).wait()).value.value == {"score": 10}, "pushed value is stored under key")

	var id := db.listen_value("players/u1/level", func(r: FirebaseResult): snapshots.append(r.value))
	await process_frame
	await db.set_value("players/u1", {"level": 4}).wait()
	await process_frame
	db.remove_listener(id)
	await db.set_value("players/u1/level", 5).wait()
	await process_frame
	check(snapshots.size() == 2 and snapshots[1].value == 4, "listener sees parent writes, then stops")

	await db.remove_value("players/u1").wait()
	check(not (await db.get_value("players/u1").wait()).value.exists, "remove deletes the value")

	for bad in ["a.b", "a/#", "a//b"]:
		result = await db.get_value(bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid path rejected: %s" % bad)
	result = await db.set_value("a", {"bad.key": 1}).wait()
	check(not result.ok, "invalid key rejected")
	result = await db.set_value("a", Vector2.ONE).wait()
	check(not result.ok, "unsupported type rejected")
