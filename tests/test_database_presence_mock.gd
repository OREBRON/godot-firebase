extends FirebaseTest


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database
	var complete := true
	for method in ["on_disconnect_set_value", "on_disconnect_update_children", "on_disconnect_remove_value", "on_disconnect_cancel", "set_network_enabled"]:
		check(db.has_method(method) and backend.has_method(method), "database API and backend implement %s" % method)
		complete = complete and db.has_method(method) and backend.has_method(method)
	check(backend.has_method("simulate_connection"), "mock exposes explicit connection fixture")
	if not complete or not backend.has_method("simulate_connection"):
		return
	for path in [".info/connected", ".info/serverTimeOffset"]:
		check((await db.get_value(path).wait()).ok, "exact .info path is readable: " + path)
		check(not (await db.set_value(path, true).wait()).ok, ".info cannot be written")
		check(not (await db.call("on_disconnect_set_value", path, false).wait()).ok, ".info cannot be queued for writing")
	for path in [".info", ".info/connected/child", "x/.info/connected", ".info/serverTimeOffset/"]:
		check(not (await db.get_value(path).wait()).ok, "only exact .info paths are readable: " + path)
	var events: Array = []
	var listener := db.listen_value(".info/connected", func(result: FirebaseResult): events.append(result.value.value))
	await process_frame
	check(events == [true], "connected listener receives current connection state")
	await db.set_value("presence/session", true).wait()
	var registration: FirebaseResult = await db.call("on_disconnect_remove_value", "presence/session").wait()
	check(registration.ok and (await db.get_value("presence/session").wait()).value.exists, "registration ACK does not execute disconnect action")
	# An active listener keeps the value in the local cache, so it can be read offline.
	var session := db.listen_value("presence/session", func(_result: FirebaseResult): pass)
	await db.call("set_network_enabled", false).wait()
	check(not (await db.get_value(".info/connected").wait()).value.value, "offline command closes the mock connection")
	check(not (await db.get_value("presence/session").wait()).value.exists, "closing the connection runs disconnect actions in the local cache")
	db.remove_listener(session)
	await db.call("set_network_enabled", true).wait()
	check(not (await db.get_value(".info/connected").wait()).value.value, "online command success is not connection confirmation")
	await process_frame
	check((await db.get_value(".info/connected").wait()).value.value, "online command reconnects")
	check(not (await db.get_value("presence/session").wait()).value.exists, "disconnect action is observed after reconnect")
	await db.set_value("presence/session", true).wait()
	backend.call("simulate_connection", false)
	backend.call("simulate_connection", true)
	check((await db.get_value("presence/session").wait()).value.exists, "disconnect registrations run once and are not replayed on reconnect")
	await db.call("on_disconnect_set_value", "presence/session", false).wait()
	await db.call("on_disconnect_cancel", "presence").wait()
	backend.call("simulate_connection", false)
	backend.call("simulate_connection", true)
	check((await db.get_value("presence/session").wait()).value.value == true, "parent cancel prevents descendant action")
	await db.call("on_disconnect_update_children", "presence", {"one": true, "nested/two": FirebaseDatabase.SERVER_TIMESTAMP}).wait()
	await db.call("on_disconnect_cancel", "presence/one").wait()
	backend.call("simulate_connection", false)
	backend.call("simulate_connection", true)
	check(not (await db.get_value("presence/one").wait()).value.exists, "child cancellation removes only that update")
	var timestamp: Variant = (await db.get_value("presence/nested/two").wait()).value.value
	check(timestamp is int and timestamp > 0, "disconnect timestamp resolves when the queued action runs")
	backend.fail_next(3, "permission denied")
	check(not (await db.call("on_disconnect_set_value", "denied", true).wait()).ok, "registration reports server rejection")
	backend.call("simulate_connection", false)
	backend.call("simulate_connection", true)
	check(not (await db.get_value("denied").wait()).value.exists, "rejected registration never executes")
	var removed_events: Array = []
	var removed := db.listen_value(".info/connected", func(result: FirebaseResult): removed_events.append(result.value))
	db.remove_listener(removed)
	await process_frame
	check(removed_events.is_empty(), "removing listener suppresses already queued initial callback")
	db.remove_listener(listener)
	var event_count := events.size()
	backend.call("simulate_connection", false)
	await process_frame
	check(events.size() == event_count, "removed connection listener remains silent")
	var pending: FirebaseTask = db.call("on_disconnect_set_value", "later", 1)
	await process_frame
	check(not pending.is_done, "offline disconnect registration waits for server acknowledgement")
	backend.call("simulate_connection", true)
	check((await pending.wait()).ok, "reconnect acknowledges pending registration")
	check(not (await db.get_value("later").wait()).value.exists, "reconnect registration ACK still does not execute action")
	var transitions: Array = []
	var transition_listener := db.listen_value(".info/connected", func(result: FirebaseResult): transitions.append(result.value.value))
	await process_frame
	backend.call("simulate_connection", false)
	backend.call("simulate_connection", true)
	await process_frame
	db.remove_listener(transition_listener)
	check(transitions == [true, false, true], "queued connection events preserve each observed state")
	await db.set_value("replace", {"stale": 1}).wait()
	await db.on_disconnect_set_value("replace", {"x": 1}).wait()
	await db.on_disconnect_set_value("replace/y", 2).wait()
	backend.simulate_connection(false)
	backend.simulate_connection(true)
	check((await db.get_value("replace").wait()).value.value == {"x": 1, "y": 2}, "child registration preserves ancestor replacement semantics")
	await db.on_disconnect_set_value("scalar", 7).wait()
	await db.on_disconnect_cancel("scalar/missing").wait()
	backend.simulate_connection(false)
	backend.simulate_connection(true)
	check((await db.get_value("scalar").wait()).value.value == 7, "child cancellation preserves queued scalar ancestor")
