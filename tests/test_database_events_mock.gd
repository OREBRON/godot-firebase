extends FirebaseTest


## A scene object that listens with its own method and is freed without remove_listener().
class ListenerOwner extends Object:
	func on_result(_result: FirebaseResult) -> void:
		pass


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database
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

	var rejected: Array[FirebaseResult] = []
	backend.fail_next(8, "permission denied")
	var denied := db.listen_value("game/score", func(result: FirebaseResult): rejected.append(result))
	await process_frame
	check((await db.set_value("game/score", 3).wait()).ok, "a failed listener consumes fail_next()")
	await process_frame
	check(denied != 0 and rejected.size() == 1, "a failed listener gets one event, then stops")
	check(rejected.size() == 1 and not rejected[0].ok and rejected[0].value == null and rejected[0].error_code == 8 and rejected[0].error_message == "permission denied", "listener failure has no snapshot")
	check(not db._listeners._callbacks.has(denied), "a failed listener is removed without remove_listener()")

	var cancelled: Array[FirebaseResult] = []
	var running := db.listen_value("game/score", func(result: FirebaseResult): cancelled.append(result))
	await process_frame
	backend.value_changed.emit(running, false, {}, 8, "permission denied")  # The server cancels it after a rules change.
	await db.set_value("game/score", 4).wait()
	await process_frame
	check(cancelled.size() == 2 and not cancelled[1].ok, "a cancelled listener gets the failure as its last event")
	check(not db._listeners._callbacks.has(running) and not backend._listeners.has(running), "a cancelled listener is removed from the backend")

	var owner := ListenerOwner.new()
	var orphan := db.listen_value("game/score", owner.on_result)
	owner.free()
	await process_frame
	check(orphan != 0 and not backend._listeners.has(orphan), "a listener whose callback object was freed is removed from the backend")
