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
const PERSISTENCE_SETTING := "firebase/database/persistence_enabled"
const MAX_DEPTH := 32
const INFO_PATHS := [".info/connected", ".info/serverTimeOffset"]

var _requests: FirebaseRequests
var _listeners: Dictionary[int, Callable] = {}


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.value_changed.connect(_on_value_changed)


func get_value(path: String) -> FirebaseTask:
	if not is_readable_path(path):
		return _invalid("not a database read path: %s" % path)
	return _requests.send(&"get_value", [path])


func set_value(path: String, value: Variant) -> FirebaseTask:
	return _write(path, &"set_value", value, [path, value])


## Writes several children at once; keys may be child paths like "stats/level".
func update_children(path: String, values: Dictionary) -> FirebaseTask:
	return _update(path, values, &"update_children")


func remove_value(path: String) -> FirebaseTask:
	return _request(path, &"remove_value", [path])


## Adds `value` under a new time-ordered key. Result value is that key.
func push_value(path: String, value: Variant) -> FirebaseTask:
	return _write(path, &"push_value", value, [path, value], 1)


## Completes after the local SDK network command, not when a connection is established.
## Observe .info/connected for this client's connection state.
func set_network_enabled(enabled: bool) -> FirebaseTask:
	return _requests.send(&"set_network_enabled", [enabled])


## Completes when the server acknowledges registration, not when the action executes.
## Register again after each reconnect. Requires a connection, not disk persistence.
func on_disconnect_set_value(path: String, value: Variant) -> FirebaseTask:
	return _write(path, &"on_disconnect_set_value", value, [path, value])


func on_disconnect_update_children(path: String, values: Dictionary) -> FirebaseTask:
	return _update(path, values, &"on_disconnect_update_children")


func on_disconnect_remove_value(path: String) -> FirebaseTask:
	return _request(path, &"on_disconnect_remove_value", [path])


## Completes when the server acknowledges cancellation at this path and its children.
func on_disconnect_cancel(path: String) -> FirebaseTask:
	return _request(path, &"on_disconnect_cancel", [path])


## Calls `callback(result: FirebaseResult)` with a snapshot now and after every change.
## Returns an id for remove_listener(), or 0 when the listener could not start.
func listen_value(path: String, callback: Callable) -> int:
	if _requests.backend == null or not is_readable_path(path) or not callback.is_valid():
		push_error("Firebase: cannot listen to %s" % path)
		return 0
	var id: int = _requests.backend.listen_value(path)
	if id != 0:
		_listeners[id] = callback
	return id


func remove_listener(id: int) -> void:
	if _listeners.erase(id):
		_requests.backend.remove_listener(id)


static func is_valid_path(path: String) -> bool:
	if path.is_empty():
		return true
	var keys := path.split("/")
	if keys.size() > MAX_DEPTH:
		return false
	for key in keys:
		if not is_valid_key(key):
			return false
	return true


static func is_valid_key(key: String) -> bool:
	if key.is_empty() or key.to_utf8_buffer().size() > 768 or not FORBIDDEN_KEY_CHARS.all(func(character): return not character in key):
		return false
	for index in key.length():
		var code := key.unicode_at(index)
		if code < 32 or code == 127:
			return false
	return true


static func is_readable_path(path: String) -> bool:
	return path in INFO_PATHS or is_valid_path(path)


## Returns an empty string when `value` can be written, otherwise the reason.
static func validate_value(value: Variant) -> String:
	return _validate_value(value, 0, [])


static func _validate_value(value: Variant, depth: int, ancestors: Array) -> String:
	if depth > MAX_DEPTH:
		return "database paths and values must not exceed 32 levels"
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(value) else "database numbers must be finite"
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if ancestors.any(func(parent): return is_same(parent, value)):
				return "cyclic database values are not supported"
			ancestors.append(value)
			for item in value:
				var reason := _validate_value(item, depth + 1, ancestors)
				if not reason.is_empty():
					ancestors.pop_back()
					return reason
			ancestors.pop_back()
			return ""
		TYPE_DICTIONARY:
			if value.size() == 1 and value.get(".sv") is String and value.get(".sv") == "timestamp":
				return ""
			if ancestors.any(func(parent): return is_same(parent, value)):
				return "cyclic database values are not supported"
			ancestors.append(value)
			for key in value:
				if not key is String or not is_valid_key(key):
					ancestors.pop_back()
					return "keys must be strings without . # $ [ ] /: %s" % str(key)
				var reason := _validate_value(value[key], depth + 1, ancestors)
				if not reason.is_empty():
					ancestors.pop_back()
					return reason
			ancestors.pop_back()
			return ""
	return "unsupported type %s" % type_string(typeof(value))


func _request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not is_valid_path(path):
		return _invalid("not a database path: %s" % path)
	return _requests.send(method, args)


func _write(path: String, method: StringName, value: Variant, args: Array, extra_depth: int = 0) -> FirebaseTask:
	var reason := _validate_value(value, _path_depth(path) + extra_depth, [])
	if not reason.is_empty():
		return _invalid(reason)
	return _request(path, method, args)


func _update(path: String, values: Dictionary, method: StringName) -> FirebaseTask:
	for key in values:
		if not key is String or not is_valid_path(key) or key.is_empty():
			return _invalid("child path must be a non-empty valid path: %s" % str(key))
		var slash: int = key.find("/")
		while slash != -1:
			if values.has(key.left(slash)):
				return _invalid("update paths must not contain both a parent and its child")
			slash = key.find("/", slash + 1)
		var reason := _validate_value(values[key], _path_depth(path) + _path_depth(key), [])
		if not reason.is_empty():
			return _invalid(reason)
	return _request(path, method, [path, values])


static func _path_depth(path: String) -> int:
	return 0 if path.is_empty() else path.split("/").size()


func _invalid(reason: String) -> FirebaseTask:
	return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)


func _on_value_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String) -> void:
	var callback: Callable = _listeners.get(listener_id, Callable())
	if callback.is_valid():
		callback.call(FirebaseResult.success(snapshot) if ok else FirebaseResult.failure(error_code, error_message))
