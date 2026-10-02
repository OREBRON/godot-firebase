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
	var late := FirebaseDatabaseMock.new()
	late.get_value("")
	check(late.call("initialize", true) == ERR_ALREADY_IN_USE, "persistence change after reference use is rejected")
