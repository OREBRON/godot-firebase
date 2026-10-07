extends FirebaseTest


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database
	check(backend.has_method("set_network_enabled"), "database backend supports network control")
	if not backend.has_method("set_network_enabled"):
		return
	check(backend.call("initialize", true) == OK and backend.get("persistence_enabled") == true, "mock accepts persistence before first reference")
	check(backend.call("initialize", false) == ERR_ALREADY_IN_USE, "persistence cannot be reconfigured after initialization")
	for enabled in [false, false, true, true]:
		check((await db.call("set_network_enabled", enabled).wait()).ok, "network command is repeatable")
	backend.call("simulate_connection", false)
	var write := db.set_value("pending", 9)
	await process_frame
	check(not write.is_done, "offline write stays pending until server acknowledgement")
	check((await db.get_value("pending").wait()).value.value == 9, "offline write appears in local cache")
	backend.call("simulate_connection", true)
	check((await write.wait()).ok, "reconnection acknowledges the pending write")
	await db.call("set_network_enabled", false).wait()
	var events: Array = []
	var listener := db.listen_value("queue", func(result: FirebaseResult): events.append(result.value.value))
	var queued := {"first": db.set_value("queue/a", 1), "registration": db.on_disconnect_remove_value("queue"), "second": db.update_children("queue", {"b": 2})}
	var acknowledged: Array = []
	for name: String in queued:
		queued[name].completed.connect(func(_result: FirebaseResult): acknowledged.append(name))
	await process_frame
	check(events == [null, {"a": 1}, {"a": 1, "b": 2}], "offline writes raise local value events at once")
	check(acknowledged.is_empty(), "offline writes and registrations wait for the server")
	await db.call("set_network_enabled", true).wait()
	await process_frame
	db.remove_listener(listener)
	check(acknowledged == ["first", "second", "registration"], "going online acknowledges queued writes in order, then registrations")
	check((await db.get_value(".info/connected").wait()).value.value, "going online opens the connection")
	backend.call("simulate_connection", false)
	await db.call("set_network_enabled", false).wait()
	await db.call("set_network_enabled", true).wait()
	await process_frame
	check(not (await db.get_value(".info/connected").wait()).value.value, "going online cannot reach an unreachable server")
	var late := FirebaseDatabaseMock.new()
	late.get_value("")
	check(late.call("initialize", true) == ERR_ALREADY_IN_USE, "persistence change after reference use is rejected")
