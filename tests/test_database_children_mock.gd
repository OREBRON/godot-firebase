extends FirebaseTest


## A scene object that listens with its own method and is freed without remove_listener().
class ListenerOwner extends Object:
	func on_result(_result: FirebaseResult) -> void:
		pass


func _run() -> void:
	var backend := FirebaseDatabaseMock.new()
	var db: FirebaseDatabase = mock_firebase({"database": backend}).database

	await db.set_value("room/players", {"b": 1, "a": 2, "10": 3, "9": 4}).wait()
	var events: Array = []
	var players := db.listen_children("room/players", _record(events))
	await process_frame
	check(events == [["added", "9", 4, null], ["added", "10", 3, "9"], ["added", "a", 2, "10"], ["added", "b", 1, "a"]], "existing children arrive as added in key order, integer keys first: %s" % str(events))
	events.clear()
	await db.set_value("room/players/c", 5).wait()
	await db.set_value("room/players/a", 7).wait()
	await db.set_value("room/players/a", 7).wait()
	await db.remove_value("room/players/9").wait()
	await process_frame
	check(events == [["added", "c", 5, "b"], ["changed", "a", 7, "10"], ["removed", "9", 4, null]], "writes raise added, changed and removed; rewriting equal data raises nothing: %s" % str(events))
	events.clear()
	await db.update_children("room/players", {"b": null, "d": 6, "10": 8}).wait()
	await process_frame
	check(events == [["removed", "b", 1, null], ["added", "d", 6, "c"], ["changed", "10", 8, null]], "one write raises removed, then added, then changed: %s" % str(events))
	events.clear()
	await db.set_value("room/players/a/x", 2).wait()
	await db.set_value("room/players", 5).wait()
	await process_frame
	check(events == [["changed", "a", {"x": 2}, "10"], ["removed", "10", 8, null], ["removed", "a", {"x": 2}, null], ["removed", "c", 5, null], ["removed", "d", 6, null]], "a nested write changes its child; a leaf removes every child in order: %s" % str(events))
	db.remove_listener(players)
	events.clear()
	await db.set_value("room/players/e", 1).wait()
	await process_frame
	check(events.is_empty() and not backend._children_sent.has(players), "remove_listener() stops child events")

	var empty_events: Array = []
	var empty := db.listen_children("nothing/here", _record(empty_events))
	await db.set_value("list", ["x", "y"]).wait()
	var list_events: Array = []
	var list := db.listen_children("list", _record(list_events))
	await process_frame
	db.remove_listener(empty)
	db.remove_listener(list)
	check(empty_events.is_empty(), "a location without children raises no event")
	check(list_events == [["added", "0", "x", null], ["added", "1", "y", "0"]], "list items are children keyed by index")

	await db.set_value("scores", {"ada": {"score": 30}, "bob": {"score": 10}, "cem": {"score": 20}}).wait()
	var ranked: Array = []
	var ranking := db.listen_children("scores", _record(ranked), {order_by = "score"})
	await process_frame
	check(ranked == [["added", "bob", {"score": 10}, null], ["added", "cem", {"score": 20}, "bob"], ["added", "ada", {"score": 30}, "cem"]], "a query adds existing children in query order: %s" % str(ranked))
	ranked.clear()
	await db.set_value("scores/cem/score", 40).wait()
	await db.set_value("scores/bob/name", "Bob").wait()
	await process_frame
	db.remove_listener(ranking)
	check(ranked == [["moved", "cem", {"score": 40}, "ada"], ["changed", "cem", {"score": 40}, "ada"], ["changed", "bob", {"name": "Bob", "score": 10}, null]], "a new sort value raises moved before changed; another change raises only changed: %s" % str(ranked))

	await db.set_value("top", {"ada": {"score": 30}, "bob": {"score": 10}, "cem": {"score": 20}}).wait()
	var top: Array = []
	var window := db.listen_children("top", _record(top), {order_by = "score", limit_to_last = 2})
	await process_frame
	check(top == [["added", "cem", {"score": 20}, null], ["added", "ada", {"score": 30}, "cem"]], "a limited query adds only the children in its window: %s" % str(top))
	top.clear()
	await db.set_value("top/dan", {"score": 25}).wait()
	await process_frame
	check(top == [["removed", "cem", {"score": 20}, null], ["added", "dan", {"score": 25}, null]], "a child entering the window removes the one it pushes out: %s" % str(top))
	top.clear()
	await db.set_value("top/bob/score", 5).wait()
	await db.set_value("top/ada/score", 1).wait()
	await process_frame
	check(top == [["removed", "ada", {"score": 30}, null], ["added", "cem", {"score": 20}, null]], "changes outside the window raise nothing; a child leaving it brings in the next: %s" % str(top))
	top.clear()
	await db.set_value("top/dan/score", 50).wait()
	await process_frame
	db.remove_listener(window)
	check(top == [["moved", "dan", {"score": 50}, "cem"], ["changed", "dan", {"score": 50}, "cem"]], "a new sort value raises moved even when the position stays: %s" % str(top))

	var rejected: Array = []
	backend.fail_next(8, "permission denied")
	var denied := db.listen_children("scores", _record(rejected))
	await process_frame
	check(denied != 0 and rejected == [8], "a failed child listener gets one failure: %s" % str(rejected))
	check(not db._listeners._callbacks.has(denied), "a failed child listener is removed without remove_listener()")

	var cancelled: Array = []
	var running := db.listen_children("scores", _record(cancelled))
	await process_frame
	backend.children_changed.emit(running, false, {}, 8, "permission denied")  # The server cancels it after a rules change.
	await db.set_value("scores/eda", {"score": 1}).wait()
	await process_frame
	check(cancelled.size() == 4 and cancelled[3] == 8, "a cancelled child listener gets the failure as its last event: %s" % str(cancelled))
	check(not db._listeners._callbacks.has(running) and not backend._listeners.has(running), "a cancelled child listener is removed from the backend")

	var owner := ListenerOwner.new()
	var orphan := db.listen_children("scores", owner.on_result)
	owner.free()
	await process_frame
	check(orphan != 0 and not backend._listeners.has(orphan), "a child listener whose callback object was freed is removed from the backend")

	var ignore := func(_result: FirebaseResult): pass
	check(db.listen_children(".info/connected", ignore) == 0, ".info paths have no child events")
	check(db.listen_children("a.b", ignore) == 0, "an invalid path cannot be listened to")
	check(db.listen_children("scores", ignore, {limit_to_first = 1}) == 0, "an invalid query cannot be listened to")


## Records each event as [event, key, value, previous_key], or a failure as its error code.
func _record(events: Array) -> Callable:
	return func(result: FirebaseResult) -> void:
		events.append([result.value.event, result.value.key, result.value.value, result.value.previous_key] if result.ok else result.error_code)
