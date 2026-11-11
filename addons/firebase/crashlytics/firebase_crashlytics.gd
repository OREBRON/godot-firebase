class_name FirebaseCrashlytics
extends RefCounted
## Tasks acknowledge local SDK calls, never report delivery or disk persistence.
## Only explicit record_error() calls report GDScript errors. Native crashes are
## captured by the platform SDK; symbolication requires matching uploaded symbols.
## Collection overrides persist across launches. Disabling may require restart;
## use export metadata for collection disabled before the first App startup.

var _requests: FirebaseRequests

func _init(requests: FirebaseRequests) -> void:
	_requests = requests

func log_message(message: String) -> FirebaseTask:
	return _requests.send(&"log_message", [message])

func set_custom_key(key: String, value: Variant) -> FirebaseTask:
	return _send(&"set_custom_key", [key, value], validate_custom_key(key, value))

## Sets every key in one call; one invalid key or value sets none of them.
func set_custom_keys(keys: Dictionary) -> FirebaseTask:
	return _send(&"set_custom_keys", [keys], validate_custom_keys(keys))

func set_user_id(user_id: String) -> FirebaseTask:
	return _requests.send(&"set_user_id", [user_id])

func clear_user_id() -> FirebaseTask:
	return _requests.send(&"clear_user_id", [])

## Frames are {function, file, line}; get_stack() frames are accepted as they are.
func record_error(name: String, message: String, stack: Array[Dictionary] = []) -> FirebaseTask:
	var frames := _with_file_keys(stack)
	return _send(&"record_error", [name, message, frames], validate_error(name, frames))

func set_collection_enabled(enabled: bool) -> FirebaseTask:
	return _requests.send(&"set_collection_enabled", [enabled])

func is_collection_enabled() -> FirebaseTask:
	return _requests.send(&"is_collection_enabled", [])

func did_crash_previous_execution() -> FirebaseTask:
	return _requests.send(&"did_crash_previous_execution", [])

## Native SDK checks once per process; later checks return false. Collection
## enabled returns false immediately without consuming the SDK's one check.
func check_unsent_reports() -> FirebaseTask:
	return _requests.send(&"check_unsent_reports", [])

func send_unsent_reports() -> FirebaseTask:
	return _requests.send(&"send_unsent_reports", [])

func delete_unsent_reports() -> FirebaseTask:
	return _requests.send(&"delete_unsent_reports", [])

func _send(method: StringName, args: Array, reason: String) -> FirebaseTask:
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _requests.send(method, args)

static func validate_custom_key(key: String, value: Variant) -> String:
	if key.is_empty():
		return "custom key must not be empty"
	if typeof(value) not in [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
		return "custom values must be String, bool, int or finite float"
	if value is float and not is_finite(value):
		return "custom numbers must be finite"
	return ""

static func validate_custom_keys(keys: Dictionary) -> String:
	for key in keys:
		if not (key is String or key is StringName):
			return "custom keys must be strings"
		var reason := validate_custom_key(key, keys[key])
		if not reason.is_empty():
			return reason
	return ""

## get_stack() names the script path "source"; the platform bridges read "file".
static func _with_file_keys(stack: Array[Dictionary]) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for frame in stack:
		var copy := frame.duplicate()
		if copy.has("source") and not copy.has("file"):
			copy.file = copy.source
			copy.erase("source")
		frames.append(copy)
	return frames

static func validate_error(name: String, stack: Array) -> String:
	if name.is_empty():
		return "error name must not be empty"
	for frame in stack:
		if not frame is Dictionary or frame.size() != 3:
			return "stack frames require exactly function, file and line"
		if not frame.get("function") is String or not frame.get("file") is String or not frame.get("line") is int:
			return "stack frames require String function/file and int line"
		if frame.line < 0 or frame.line > 2147483647:
			return "stack frame line must fit a non-negative signed 32-bit integer"
	return ""
