extends FirebaseTest
## Every listen method refuses a callback that can never be called: it returns 0
## and logs why before the backend subscribes.


class ListenErrors extends Logger:
	var messages: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR and code.begins_with("Firebase: cannot listen to "):
			_mutex.lock()
			messages.append(code)
			_mutex.unlock()


class ListenerOwner extends Object:
	func on_result(_result: FirebaseResult) -> void:
		pass


func _run() -> void:
	var firestore_backend := FirebaseFirestoreMock.new()
	var database_backend := FirebaseDatabaseMock.new()
	var firebase := mock_firebase({"firestore": firestore_backend, "database": database_backend})
	var firestore: FirebaseFirestore = firebase.firestore
	var database: FirebaseDatabase = firebase.database
	var listens: Array[Array] = [
		["listen_doc", firestore_backend, func(callback: Callable) -> int: return firestore.listen_doc("scores/a", callback)],
		["listen_query", firestore_backend, func(callback: Callable) -> int: return firestore.listen_query("scores", callback)],
		["listen_value", database_backend, func(callback: Callable) -> int: return database.listen_value("game", callback)],
		["listen_children", database_backend, func(callback: Callable) -> int: return database.listen_children("game", callback)],
	]
	var owner := ListenerOwner.new()
	var freed := owner.on_result
	owner.free()
	var errors := ListenErrors.new()
	OS.add_logger(errors)
	for callback: Callable in [Callable(), freed]:
		for listen in listens:
			var backend: FirebaseMockModule = listen[1]
			var calls_before := backend._next_id
			var logged := errors.messages.size()
			check(listen[2].call(callback) == 0, "%s refuses an invalid callback" % listen[0])
			check(backend._next_id == calls_before, "%s does not reach the backend with an invalid callback" % listen[0])
			check(errors.messages.size() == logged + 1, "%s logs why it did not start" % listen[0])
	OS.remove_logger(errors)
