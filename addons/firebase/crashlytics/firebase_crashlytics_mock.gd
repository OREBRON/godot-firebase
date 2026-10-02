class_name FirebaseCrashlyticsMock
extends FirebaseMockModule
## In-memory observations only: no crash capture, disk cache or upload simulation.

var logs: Array[String] = []
var custom_keys := {}
var user_id := ""
var errors: Array[Dictionary] = []
var collection_enabled := true
var previous_execution_crashed := false
var unsent_reports := false
var send_requested := false
var delete_requested := false
var _reports_checked := false

func log_message(message: String) -> int:
	return _apply(func(): logs.append(message))

func set_custom_key(key: String, value: Variant) -> int:
	return _apply(func(): custom_keys[key] = value)

func set_user_id(value: String) -> int:
	return _apply(func(): user_id = value)

func clear_user_id() -> int:
	return _apply(func(): user_id = "")

func record_error(name: String, message: String, stack: Array[Dictionary] = []) -> int:
	return _apply(func(): errors.append({"name": name, "message": message, "stack": stack.duplicate(true)}))

func set_collection_enabled(enabled: bool) -> int:
	return _apply(func(): collection_enabled = enabled)

func is_collection_enabled() -> int:
	return _apply(func(): return collection_enabled)

func did_crash_previous_execution() -> int:
	return _apply(func(): return previous_execution_crashed)

func check_unsent_reports() -> int:
	return _apply(func():
		if collection_enabled or _reports_checked:
			return false
		_reports_checked = true
		return unsent_reports)

func send_unsent_reports() -> int:
	return _apply(func():
		if not collection_enabled:
			send_requested = true)

func delete_unsent_reports() -> int:
	return _apply(func():
		if not collection_enabled:
			delete_requested = true)

func _apply(action: Callable) -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, action.call())
	return id
