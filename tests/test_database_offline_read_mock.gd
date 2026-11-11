extends FirebaseTest
## Like the SDKs' single value listener, an offline read is answered from the local
## cache or, without the value there, after the connection returns.


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database
	await db.set_value("config", {"motd": "hi", "level": 1}).wait()
	var level := db.listen_value("config/level", func(_result: FirebaseResult): pass)
	backend.simulate_connection(false)
	var read := db.get_value("config")
	await process_frame
	check(not read.is_done, "an offline read of uncached data waits for the connection")
	check((await read.wait(0.1)).error_code == FirebaseResult.ERR_TIMEOUT, "wait(timeout_seconds) bounds that wait")
	check((await db.get_value("config/level").wait()).value.value == 1, "an active listener answers offline reads of its value")
	db.remove_listener(level)
	var write := db.set_value("draft", {"text": "a"})
	check((await db.get_value("draft/text").wait()).value.value == "a", "a pending write answers offline reads below it")
	var order: Array = []
	read.completed.connect(func(_result: FirebaseResult): order.append("read"))
	write.completed.connect(func(_result: FirebaseResult): order.append("write"))
	backend.simulate_connection(true)
	check((await read.wait()).value.value == {"level": 1, "motd": "hi"}, "the waiting read is answered after reconnecting")
	await write.wait()
	check(order == ["read", "write"], "reconnecting answers waiting reads before acknowledging queued writes")

	var persisted := FirebaseDatabaseMock.new()
	persisted.initialize(true)
	db = mock_firebase({"database": persisted}).database
	var first := {order_by = "$key", limit_to_first = 1}
	await db.set_value("saved", {"coins": 3}).wait()
	await db.get_value("shop", first).wait()
	await db.on_disconnect_set_value("status", "away").wait()
	persisted.simulate_connection(false)
	check((await db.get_value("saved/coins").wait()).value.value == 3, "with persistence a written value stays readable offline")
	check((await db.get_value("shop", first).wait()).ok, "with persistence a query read before is answered offline")
	check((await db.get_value("status").wait()).value.value == "away", "with persistence a disconnect action stays readable offline")
	var whole := db.get_value("shop")
	await process_frame
	check(not whole.is_done, "with persistence a value never loaded still waits for the connection")
	persisted.simulate_connection(true)
	check((await whole.wait()).ok, "the waiting read is answered after reconnecting")
