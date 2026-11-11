extends FirebaseTest
## wait(timeout_seconds) ends only that wait; the request keeps running.


func _run() -> void:
	var db: FirebaseFirestore = mock_firebase().firestore
	var result := await db.get_doc("saves/a").wait(5.0)
	check(result.ok, "result that arrives in time is returned")

	await db.set_network_enabled(false).wait()
	var write := db.set_doc("saves/a", {"level": 1})
	var untimed: Array[FirebaseResult] = []
	var wait_without_timeout := func() -> void: untimed.append(await write.wait())
	wait_without_timeout.call()
	result = await write.wait(0.1)
	check(not result.ok and result.error_code == FirebaseResult.ERR_TIMEOUT, "offline write wait times out")
	check(not write.is_done and untimed.is_empty(), "timeout neither finishes the task nor ends other waits")

	await db.set_network_enabled(true).wait()
	result = await write.wait(5.0)
	check(result.ok and write.result == result, "write finishes later with its real result")
	check(untimed.size() == 1 and untimed[0] == result, "wait without timeout gets the same result")
	result = await write.wait(0.1)
	check(result.ok, "finished task returns its result, not a timeout")
	result = await db.get_doc("saves/a", "server").wait()
	check(result.ok and result.value.data.level == 1, "timed-out write still reached the server")
