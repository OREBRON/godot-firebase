extends FirebaseTest

var snapshots: Array = []


func _run() -> void:
	var firebase := mock_firebase({"firestore": FirebaseFirestoreMock.new()})
	var db: FirebaseFirestore = firebase.firestore
	var path := "batches/existing"
	await db.set_doc(path, {"score": 10, "profile": {"name": "Ada", "count": 1}}).wait()

	var listener_id := db.listen_doc(path, func(r: FirebaseResult): snapshots.append(r.value))
	await process_frame
	check(snapshots.size() == 1, "listener receives the initial document")

	var result := await db.batch([
		{"op": "delete", "path": path},
		{"op": "update", "path": path, "data": {"score": 20}},
	]).wait()
	check(not result.ok and result.error_code == FirebaseFirestoreMock.NOT_FOUND, "delete then update fails with NOT_FOUND")
	var doc: Dictionary = (await db.get_doc(path).wait()).value
	check(doc.exists and doc.data == {"score": 10, "profile": {"name": "Ada", "count": 1}}, "failed delete then update preserves the document")
	await process_frame
	check(snapshots.size() == 1, "failed delete then update does not notify listeners")
	db.remove_listener(listener_id)
	snapshots.clear()

	result = await db.batch([
		{"op": "set", "path": "batches/new", "data": {"score": 10}},
		{"op": "update", "path": "batches/new", "data": {"score": FirebaseValue.increment(5)}},
	]).wait()
	check(result.ok, "set then update succeeds for a previously missing document")
	doc = (await db.get_doc("batches/new").wait()).value
	check(doc.exists and doc.data == {"score": 15}, "update sees the preceding set in the batch")

	await db.set_doc(path, {"score": 10, "profile": {"name": "Ada", "count": 1}}).wait()
	listener_id = db.listen_doc(path, func(r: FirebaseResult): snapshots.append(r.value))
	await process_frame
	result = await db.batch([
		{"op": "update", "path": path, "data": {"profile.count": FirebaseValue.increment(2)}},
		{"op": "set", "path": path, "data": {"profile": {"name": "Bea"}}, "merge": true},
		{"op": "set", "path": "batches/rolled_back", "data": {"score": 99}},
		{"op": "delete", "path": path},
		{"op": "update", "path": path, "data": {"score": 20}},
	]).wait()
	check(not result.ok and result.error_code == FirebaseFirestoreMock.NOT_FOUND, "a later update failure rejects the entire batch")
	doc = (await db.get_doc(path).wait()).value
	check(doc.exists and doc.data == {"score": 10, "profile": {"name": "Ada", "count": 1}}, "failed batch rolls back nested updates and merge sets")
	check(not (await db.get_doc("batches/rolled_back").wait()).value.exists, "failed batch rolls back new documents")
	await process_frame
	check(snapshots.size() == 1, "rolled back batch does not notify listeners")

	result = await db.batch([
		{"op": "delete", "path": path},
		{"op": "set", "path": path, "data": {"profile": {"count": 4}}},
		{"op": "update", "path": path, "data": {"profile.count": FirebaseValue.increment(2)}},
	]).wait()
	check(result.ok, "delete then set then update succeeds")
	doc = (await db.get_doc(path).wait()).value
	check(doc.exists and doc.data == {"profile": {"count": 6}}, "successful batch applies all writes in order")
	await process_frame
	check(snapshots.size() == 2, "successful batch notifies the listener once")
	check(snapshots.size() == 2 and snapshots[1].data == {"profile": {"count": 6}}, "listener receives only the committed document")
	db.remove_listener(listener_id)
