extends FirebaseTest


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database
	check(FirebaseDatabase.increment(2) == {".sv": {"increment": 2}}, "increment() is the Realtime Database server value")
	check((await db.set_value("counter", FirebaseDatabase.increment(2)).wait()).ok, "increment can be written")
	check((await db.get_value("counter").wait()).value.value == 2, "a missing value becomes the increment")
	await db.set_value("counter", FirebaseDatabase.increment(3)).wait()
	var counter: Variant = (await db.get_value("counter").wait()).value.value
	check(counter is int and counter == 5, "integer increments keep an int")
	await db.set_value("counter", FirebaseDatabase.increment(-0.5)).wait()
	check((await db.get_value("counter").wait()).value.value == 4.5, "a float increment adds to the stored number")
	await db.set_value("stats", {"wins": 1, "name": "Ada"}).wait()
	await db.update_children("stats", {"wins": FirebaseDatabase.increment(1), "name": FirebaseDatabase.increment(1)}).wait()
	check((await db.get_value("stats").wait()).value.value == {"name": 1, "wins": 2}, "update increments each child and replaces a non-number")
	await db.set_value("stats", {"wins": FirebaseDatabase.increment(10), "list": [FirebaseDatabase.increment(1)]}).wait()
	check((await db.get_value("stats").wait()).value.value == {"list": [1], "wins": 12}, "nested increments add to the value they replace")

	await db.set_value("room/players", 2).wait()
	await db.on_disconnect_set_value("room/players", FirebaseDatabase.increment(-1)).wait()
	backend.simulate_connection(false)
	var offline_write := db.set_value("offline", FirebaseDatabase.increment(1))
	check((await db.get_value("offline").wait()).value.value == 1, "an offline increment shows locally at once")
	backend.simulate_connection(true)
	check((await db.get_value("room/players").wait()).value.value == 1, "a disconnect increment applies to the value at disconnect")
	check((await offline_write.wait()).ok, "the queued increment is acknowledged on reconnect")
	check((await db.get_value("offline").wait()).value.value == 1, "the queued increment applies once")

	for value in [FirebaseDatabase.increment("1"), FirebaseDatabase.increment(true), FirebaseDatabase.increment(INF), {".sv": {"increment": 1, "extra": 1}}, {".sv": "other"}]:
		check(not (await db.set_value("counter", value).wait()).ok, "invalid server value is rejected: %s" % str(value))
