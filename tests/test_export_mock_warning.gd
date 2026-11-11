extends FirebaseTest
## Exported desktop games have no Firebase SDK; each mock backend must warn at runtime.


class MockWarningLogger extends Logger:
	var messages: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING and "in-memory mock" in code:
			_mutex.lock()
			messages.append(code)
			_mutex.unlock()


func _run() -> void:
	var warnings := MockWarningLogger.new()
	OS.add_logger(warnings)
	var firebase: Node = FirebaseNode.new()
	check(not firebase._exported, "editor run is not an exported build")
	check(firebase._create_backend("auth", false) is FirebaseMockModule and warnings.messages.is_empty(), "editor mock starts without a warning")
	firebase._exported = true
	check(firebase._create_backend("auth", false) is FirebaseMockModule, "exported desktop build keeps the mock")
	check(warnings.messages.size() == 1 and warnings.messages[0].begins_with("Firebase: auth "), "exported mock warns at runtime")
	OS.remove_logger(warnings)
	firebase.free()
