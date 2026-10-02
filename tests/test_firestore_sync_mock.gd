extends FirebaseTest


func _run() -> void:
	var backend := FirebaseFirestoreMock.new()
	var db: RefCounted = mock_firebase({"firestore": backend}).firestore
	check(db.has_method("query_snapshot") and db.has_method("wait_pending_writes"), "sync API is available")
	if not db.has_method("query_snapshot"):
		return
	var result: FirebaseResult = await db.get_doc("saves/missing", "cache").wait()
	check(not result.ok and result.error_code == 14, "unknown cache document fails")
	result = await db.query_snapshot("empty", [], [], 0, "cache").wait()
	check(result.ok and result.value.documents == [] and result.value.metadata == {"is_from_cache": true, "has_pending_writes": false}, "empty query carries cache metadata")
	result = await db.query("empty", [], [], 0, "cache").wait()
	check(result.ok and result.value is Array, "legacy query still returns Array")
	result = await db.get_doc("saves/unknown").wait()
	check(result.ok and not result.value.exists and not result.value.metadata.is_from_cache, "server confirms missing document")
	result = await db.get_doc("saves/unknown", "cache").wait()
	check(result.ok and not result.value.exists and result.value.metadata.is_from_cache, "confirmed absence is cached")
	for method in ["get_doc", "query", "query_snapshot"]:
		var args: Array = ["saves/a", "invalid"] if method == "get_doc" else ["saves", [], [], 0, "invalid"]
		result = await db.callv(method, args).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid source rejected: " + method)
	await db.set_doc("saves/a", {"level": 1}).wait()
	var normal: Array = []
	var metadata: Array = []
	var normal_id: int = db.listen_doc("saves/a", func(r): normal.append(r.value))
	var metadata_id: int = db.listen_doc("saves/a", func(r): metadata.append(r.value), true)
	await process_frame
	await db.set_network_enabled(false).wait()
	await process_frame
	check(normal.size() == 1 and metadata.size() == 2 and metadata[-1].metadata.is_from_cache, "only opted-in listener receives network metadata change")
	var write: FirebaseTask = db.set_doc("saves/a", {"level": 2})
	await process_frame
	check(not write.is_done, "offline write task awaits server ACK")
	check(normal.size() == 2 and normal[-1].data.level == 2 and normal[-1].metadata.has_pending_writes, "local pending snapshot is visible before ACK")
	result = await db.get_doc("saves/a", "cache").wait()
	check(result.ok and result.value.metadata.has_pending_writes and result.value.metadata.is_from_cache, "cache source exposes pending state")
	result = await db.query_snapshot("saves", [], [], 0, "cache").wait()
	check(result.ok and result.value.metadata.has_pending_writes, "query metadata summarizes pending matching documents")
	result = await db.get_doc("saves/a", "server").wait()
	check(not result.ok and result.error_code == 14, "server source fails offline")
	result = await db.query_snapshot("saves", [], [], 0, "server").wait()
	check(not result.ok and result.error_code == 14, "server query fails offline")
	var barrier: FirebaseTask = db.wait_pending_writes()
	var later: FirebaseTask = db.set_doc("saves/b", {"level": 3})
	await process_frame
	check(not barrier.is_done, "barrier waits for writes pending at call time")
	backend.call("set_auto_acknowledge", false)
	await db.set_network_enabled(true).wait()
	backend.call("acknowledge_pending_writes", 1)
	await process_frame
	check(write.is_done and write.result.ok and barrier.is_done and barrier.result.ok and not later.is_done, "barrier excludes writes enqueued later")
	check(normal.size() == 2 and not metadata[-1].metadata.has_pending_writes, "ACK-only snapshot obeys metadata opt-in")
	backend.call("acknowledge_pending_writes")
	await later.wait()
	db.remove_listener(normal_id)
	db.remove_listener(metadata_id)
	var before := metadata.size()
	await db.set_network_enabled(false).wait()
	await process_frame
	check(metadata.size() == before, "removed listener receives no callbacks")
	var pending: FirebaseTask = db.set_doc("saves/c", {"level": 4})
	var user_barrier: FirebaseTask = db.wait_pending_writes()
	backend.call("simulate_user_change", "another-user")
	result = await user_barrier.wait()
	check(not result.ok and result.error_code == 1, "user change cancels pending-writes barrier")
	check(not pending.is_done, "changing user does not discard the original write task")
	backend.call("simulate_user_change", "")
	await db.set_network_enabled(true).wait()
	backend.call("acknowledge_pending_writes")
	await pending.wait()
	result = await db.wait_pending_writes().wait()
	check(result.ok, "empty pending-writes barrier completes")

	backend.call("set_auto_acknowledge", true)
	await db.set_network_enabled(false).wait()
	backend.call("simulate_user_change", "user-a")
	var user_a_write: FirebaseTask = db.set_doc("saves/account", {"level": 5})
	backend.call("simulate_user_change", "user-b")
	await db.set_network_enabled(true).wait()
	await process_frame
	check(not user_a_write.is_done, "another user cannot ACK the original user's queued write")
	backend.call("simulate_user_change", "user-a")
	var returned_barrier: FirebaseTask = db.wait_pending_writes()
	await process_frame
	check(user_a_write.is_done and returned_barrier.is_done, "returning to an online user resumes its automatic ACKs")
	backend.call("acknowledge_pending_writes")
