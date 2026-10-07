extends FirebaseTest


func _run() -> void:
	var db: FirebaseDatabase = mock_firebase({"database": FirebaseDatabaseMock.new()}).database
	var connected: Array = []
	var connection := db.listen_value(".info/connected", func(result: FirebaseResult): connected.append(result.value.value))
	var offset := await db.get_value(".info/serverTimeOffset").wait()
	check(offset.ok and not offset.value.exists and offset.value.value == null, "server time offset is unknown before the first connection")
	await process_frame
	db.remove_listener(connection)
	check(connected == [false, true], ".info/connected starts false and becomes true shortly after start")
	offset = await db.get_value(".info/serverTimeOffset").wait()
	check(offset.value.exists and offset.value.value is int, "server time offset is known once connected")

	var scores: Array = []
	var score := db.listen_value("game/score", func(result: FirebaseResult): scores.append(result.value.value))
	var games: Array = []
	var game := db.listen_value("game", func(result: FirebaseResult): games.append(result.value.value))
	await process_frame
	await db.set_value("game/score", 1).wait()
	await db.set_value("game/score", 1).wait()
	await db.set_value("game/other", 2).wait()
	await db.update_children("game", {"score": 1, "other": 2}).wait()
	await db.set_value("game", {"other": 2, "score": 1}).wait()
	await db.remove_value("game/missing").wait()
	await db.set_value("game/score", 2).wait()
	await process_frame
	check(scores == [null, 1, 2], "a value listener fires only when its value changes")
	check(games == [null, {"score": 1}, {"score": 1, "other": 2}, {"score": 2, "other": 2}], "rewriting equal data raises no value event")
	await db.set_network_enabled(false).wait()
	await db.set_network_enabled(true).wait()
	await process_frame
	db.remove_listener(score)
	db.remove_listener(game)
	check(scores == [null, 1, 2], "reconnecting without changes raises no value event")
