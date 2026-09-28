class_name FirebaseDatabase
extends RefCounted
## Realtime Database API.
##
## Paths are slash-separated keys; "" is the root. Snapshots are
## {key, exists, value}. Values are null, bool, int, float, String, Array and
## Dictionary with String keys.

## Write it as a value; the server stores its time in Unix milliseconds.
const SERVER_TIMESTAMP := {".sv": "timestamp"}
const FORBIDDEN_KEY_CHARS := [".", "#", "$", "[", "]", "/"]

var _requests: FirebaseRequests
var _listeners: Dictionary[int, Callable] = {}


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.value_changed.connect(_on_value_changed)


func get_value(path: String) -> FirebaseTask:
	return _request(path, &"get_value", [path])


func set_value(path: String, value: Variant) -> FirebaseTask:
	return _write(path, &"set_value", value, [path, value])


## Writes several children at once; keys may be child paths like "stats/level".
func update_children(path: String, values: Dictionary) -> FirebaseTask:
	for key in values:
		if not key is String or not is_valid_path(key) or key.is_empty():
			return _invalid("child path must be a non-empty valid path: %s" % str(key))
	return _write(path, &"update_children", values.values(), [path, values])


func remove_value(path: String) -> FirebaseTask:
	return _request(path, &"remove_value", [path])


## Adds `value` under a new time-ordered key. Result value is that key.
func push_value(path: String, value: Variant) -> FirebaseTask:
	return _write(path, &"push_value", value, [path, value])


## Calls `callback(result: FirebaseResult)` with a snapshot now and after every change.
## Returns an id for remove_listener(), or 0 when the listener could not start.
func listen_value(path: String, callback: Callable) -> int:
	if _requests.backend == null or not is_valid_path(path):
		push_error("Firebase: cannot listen to %s" % path)
		return 0
	var id: int = _requests.backend.listen_value(path)
	_listeners[id] = callback
	return id


func remove_listener(id: int) -> void:
	if _listeners.erase(id):
		_requests.backend.remove_listener(id)


static func is_valid_path(path: String) -> bool:
	if path.is_empty():
		return true
	for key in path.split("/"):
		if not is_valid_key(key):
			return false
	return true


static func is_valid_key(key: String) -> bool:
	return not key.is_empty() and FORBIDDEN_KEY_CHARS.all(func(character): return not character in key)


## Returns an empty string when `value` can be written, otherwise the reason.
static func validate_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			for item in value:
				var reason := validate_value(item)
				if not reason.is_empty():
					return reason
			return ""
		TYPE_DICTIONARY:
			if value == SERVER_TIMESTAMP:
				return ""
			for key in value:
				if not key is String or not is_valid_key(key):
					return "keys must be strings without . # $ [ ] /: %s" % str(key)
				var reason := validate_value(value[key])
				if not reason.is_empty():
					return reason
			return ""
	return "unsupported type %s" % type_string(typeof(value))


func _request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not is_valid_path(path):
		return _invalid("not a database path: %s" % path)
	return _requests.send(method, args)


func _write(path: String, method: StringName, value: Variant, args: Array) -> FirebaseTask:
	var reason := validate_value(value)
	if not reason.is_empty():
		return _invalid(reason)
	return _request(path, method, args)


func _invalid(reason: String) -> FirebaseTask:
	return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)


func _on_value_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String) -> void:
	var callback: Callable = _listeners.get(listener_id, Callable())
	if callback.is_valid():
		callback.call(FirebaseResult.success(snapshot) if ok else FirebaseResult.failure(error_code, error_message))
