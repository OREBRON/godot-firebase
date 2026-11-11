extends FirebaseTest
## listen_query() and count() against the mock.

var backend: FirebaseFirestoreMock
var db: FirebaseFirestore


func _run() -> void:
	backend = FirebaseFirestoreMock.new()
	db = mock_firebase({"firestore": backend}).firestore
	await _listen_query()
	await _listener_failures()
	await _count()


func _listen_query() -> void:
	await db.batch([
		{"op": "set", "path": "rooms/r1/chat/m1", "data": {"at": 1, "text": "hi"}},
		{"op": "set", "path": "rooms/r1/chat/m2", "data": {"at": 2, "text": "yo"}},
	]).wait()
	var latest: Array[FirebaseResult] = []
	var page: Array[FirebaseResult] = []
	var metadata: Array[FirebaseResult] = []
	var latest_id := db.listen_query("rooms/r1/chat", func(r: FirebaseResult): latest.append(r), [], [["at", "desc"]], 2)
	var page_id := db.listen_query("rooms/r1/chat", func(r: FirebaseResult): page.append(r), [], [["at", "asc"]], 0, {start_after = [1]})
	var metadata_id := db.listen_query("rooms/r1/chat", func(r: FirebaseResult): metadata.append(r), [], [], 0, {}, true)
	check(latest_id != 0 and page_id != 0 and metadata_id != 0, "query listeners start")
	await process_frame
	check(latest.size() == 1 and latest[0].ok and _ids(latest[0]) == ["m2", "m1"], "the first event holds the current results")
	check(latest[0].value.metadata == {"is_from_cache": false, "has_pending_writes": false}, "query events carry query metadata")
	check(page.size() == 1 and _ids(page[0]) == ["m2"], "a cursor limits a listened query")

	backend.set_auto_acknowledge(false)
	await process_frame
	db.set_doc("rooms/r1/chat/m3", {"at": 3, "text": "new"})
	await process_frame
	check(latest.size() == 2 and _ids(latest[1]) == ["m3", "m2"] and latest[1].value.metadata.has_pending_writes, "a local write is reported before the server ACK")
	check(page.size() == 2 and _ids(page[1]) == ["m2", "m3"], "every listener on the collection sees the write")
	backend.acknowledge_pending_writes()
	await process_frame
	check(latest.size() == 2, "an ACK alone changes only metadata")
	check(metadata.size() == 3 and not metadata[2].value.metadata.has_pending_writes, "include_metadata_changes reports the ACK")
	backend.set_auto_acknowledge(true)

	await db.set_doc("rooms/r2/chat/m1", {"at": 9}).wait()
	await db.set_doc("rooms/r1/chat/m1", {"at": 1, "text": "edited"}).wait()
	await process_frame
	check(latest.size() == 2 and page.size() == 2, "writes outside the results send no event")
	await db.update_doc("rooms/r1/chat/m2", {"text": "changed"}).wait()
	await process_frame
	check(latest.size() == 3 and latest[2].value.documents[1].data.text == "changed", "a changed result document sends an event")
	check(page.size() == 3 and _ids(page[2]) == ["m2", "m3"], "a changed page document sends an event")

	db.remove_listener(latest_id)
	db.remove_listener(page_id)
	db.remove_listener(metadata_id)
	var before := [latest.size(), page.size(), metadata.size()]
	await db.delete_doc("rooms/r1/chat/m3").wait()
	await process_frame
	check([latest.size(), page.size(), metadata.size()] == before, "removed query listeners get no more events")


func _listener_failures() -> void:
	check(db.listen_query("rooms", func(_r): pass, [], [], 0, {start_after = [1]}) == 0, "an invalid listened query is rejected")
	check(db.listen_query("rooms/r1", func(_r): pass) == 0, "a document path is rejected")
	var rejected: Array[FirebaseResult] = []
	backend.fail_next(7, "permission denied")
	var denied := db.listen_query("rooms/r1/chat", func(r: FirebaseResult): rejected.append(r))
	await process_frame
	await db.set_doc("rooms/r1/chat/m4", {"at": 4}).wait()
	await process_frame
	check(denied != 0 and rejected.size() == 1 and not rejected[0].ok and rejected[0].error_code == 7 and rejected[0].value == null, "a failed query listener gets one failure event")
	check(not db._listeners.has(denied) and not backend._listeners.has(denied), "a failed query listener is removed")


func _count() -> void:
	await db.batch([
		{"op": "set", "path": "scores/a", "data": {"score": 30}},
		{"op": "set", "path": "scores/b", "data": {"score": 10}},
		{"op": "set", "path": "scores/c", "data": {"name": "no score"}},
		{"op": "set", "path": "scores/c/sub/x", "data": {"score": 99}},
	]).wait()
	var result := await db.count("scores").wait()
	check(result.ok and result.value == 3, "count counts the direct children")
	result = await db.count("scores", [["score", ">", 5]]).wait()
	check(result.ok and result.value == 2, "count applies filters")
	result = await db.count("empty").wait()
	check(result.ok and result.value == 0, "an empty collection counts 0")

	backend.set_auto_acknowledge(false)
	var write := db.set_doc("scores/d", {"score": 50})
	result = await db.count("scores").wait()
	check(result.ok and result.value == 3, "count runs on the server and skips unacknowledged writes")
	backend.acknowledge_pending_writes()
	await write.wait()
	result = await db.count("scores").wait()
	check(result.ok and result.value == 4, "an acknowledged write is counted")
	backend.set_auto_acknowledge(true)

	await db.set_network_enabled(false).wait()
	result = await db.count("scores").wait()
	check(not result.ok and result.error_code == 14, "count fails offline")
	await db.set_network_enabled(true).wait()
	result = await db.count("scores/a").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "count needs a collection path")


func _ids(result: FirebaseResult) -> Array:
	return result.value.documents.map(func(doc): return doc.id)
