extends FirebaseTest
## A request rejected for an invalid argument is logged at call time, so a call
## that nobody awaits does not drop it silently.


class RejectionLogger extends Logger:
	var messages: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR and code.begins_with("Firebase: "):
			_mutex.lock()
			messages.append(code)
			_mutex.unlock()


func _run() -> void:
	var errors := RejectionLogger.new()
	OS.add_logger(errors)
	var analytics: FirebaseAnalytics = mock_firebase().analytics
	analytics.log_event("1bad")
	check(errors.messages.size() == 1, "fire-and-forget rejection is logged at call time")
	var result: FirebaseResult = await analytics.log_event("1bad").wait()
	check(errors.messages.size() == 2 and errors.messages[1] == "Firebase: invalid argument: " + result.error_message, "log carries the reason of the result")
	result = await analytics.log_event("level_end").wait()
	check(result.ok and errors.messages.size() == 2, "accepted request is not logged")
	result = await FirebaseRequests.new(null).send(&"log_event", ["level_end"]).wait()
	check(result.error_code == FirebaseResult.ERR_UNAVAILABLE and errors.messages.size() == 2, "unavailable backend is not logged per request")
	OS.remove_logger(errors)
