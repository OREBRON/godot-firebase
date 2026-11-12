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
const QUERY_BOUNDS := ["start_at", "end_at", "equal_to"]
const QUERY_LIMITS := ["limit_to_first", "limit_to_last"]
const MAX_QUERY_LIMIT := 2147483647

var _requests: FirebaseRequests
var _listeners: FirebaseListeners


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	_listeners = FirebaseListeners.new(_requests.backend)
	if _requests.backend:
		_requests.backend.value_changed.connect(_listeners.deliver)
		_requests.backend.children_changed.connect(_listeners.deliver)


## Write it as a value to add `by` to the stored number on the server atomically.
## A missing or non-number value becomes `by`.
static func increment(by: Variant) -> Dictionary:
	return {".sv": {"increment": by}}


## `query` sorts and filters the children of `path`:
## {order_by = "$key" | "$value" | "child/path", start_at, end_at, equal_to,
## limit_to_first, limit_to_last}. With a query, the snapshot value is a
## Dictionary of the matching children in query order, or null when none match.
## Without a connection the read does not fail: unless the local cache holds the
## value, it waits for the connection. Bound that wait with wait(timeout_seconds).
func get_value(path: String, query: Dictionary = {}) -> FirebaseTask:
	var reason := _read_reason(path, query)
	if not reason.is_empty():
		return _requests.invalid(reason)
	return _requests.send(&"get_value", [path, query])


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
## A failed result is the last one: the listener is already removed when it arrives.
## `query` is the get_value() query. Returns an id for remove_listener(), or 0
## when the listener could not start.
func listen_value(path: String, callback: Callable, query: Dictionary = {}) -> int:
	return _listen(&"listen_value", path, callback, query, _read_reason(path, query))


## Calls `callback(result: FirebaseResult)` once per change to a child of `path`.
## result.value is {event, key, value, previous_key}: `event` is "added", "changed",
## "moved" or "removed", `value` the child's new value (its last value when removed)
## and `previous_key` the key of the child before it in query order, or null for the
## first child and for "removed". Existing children arrive first as "added". `query`
## is the get_value() query; a child that enters or leaves a limited query's window
## arrives as "added" or "removed". A failed result is the last one.
## Returns an id for remove_listener(), or 0 when the listener could not start.
func listen_children(path: String, callback: Callable, query: Dictionary = {}) -> int:
	var reason := _read_reason(path, query) if is_valid_path(path) else "not a database path: %s" % path
	return _listen(&"listen_children", path, callback, query, reason)


func remove_listener(id: int) -> void:
	_listeners.remove(id)


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
			var server_value: Variant = value.get(".sv") if value.size() == 1 else null
			if server_value is String and server_value == "timestamp":
				return ""
			if server_value is Dictionary and server_value.size() == 1 and server_value.has("increment"):
				var by: Variant = server_value.increment
				return "" if by is int or by is float and is_finite(by) else "increment() needs a finite number"
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


## Returns an empty string when `path` can be read with `query`, otherwise the reason.
## Invalid queries abort or throw in the SDKs.
static func _read_reason(path: String, query: Dictionary) -> String:
	if query.is_empty():
		return "" if is_readable_path(path) else "not a database read path: %s" % path
	if not is_valid_path(path):
		return "not a database query path: %s" % path
	for key in query:
		if not key in ["order_by"] + QUERY_BOUNDS + QUERY_LIMITS:
			return "unknown query key: %s" % str(key)
	var order: Variant = query.get("order_by")
	if not order is String or not (order in ["$key", "$value"] or not order.is_empty() and is_valid_path(order)):
		return "order_by must be \"$key\", \"$value\" or a child path"
	if query.has("equal_to") and (query.has("start_at") or query.has("end_at")):
		return "equal_to cannot be combined with start_at or end_at"
	if query.has("limit_to_first") and query.has("limit_to_last"):
		return "use only one of limit_to_first and limit_to_last"
	for key in QUERY_BOUNDS:
		if query.has(key) and not _is_query_bound(query[key], order == "$key"):
			return "%s must be a String with $key, otherwise a bool, finite number or String" % key
	for key in QUERY_LIMITS:
		if query.has(key) and not (query[key] is int and query[key] >= 1 and query[key] <= MAX_QUERY_LIMIT):
			return "%s must be an int from 1 to %d" % [key, MAX_QUERY_LIMIT]
	return ""


static func _is_query_bound(bound: Variant, by_key: bool) -> bool:
	return bound is String or not by_key and (bound is bool or bound is int or bound is float and is_finite(bound))


func _listen(method: StringName, path: String, callback: Callable, query: Dictionary, reason: String) -> int:
	if _requests.backend == null or not reason.is_empty() or not callback.is_valid():
		push_error("Firebase: cannot listen to %s: %s" % [path, reason if reason else "no backend or invalid callback"])
		return 0
	return _listeners.add(_requests.backend.call(method, path, query), callback)


func _request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not is_valid_path(path):
		return _requests.invalid("not a database path: %s" % path)
	return _requests.send(method, args)


func _write(path: String, method: StringName, value: Variant, args: Array, extra_depth: int = 0) -> FirebaseTask:
	var reason := _validate_value(value, _path_depth(path) + extra_depth, [])
	if not reason.is_empty():
		return _requests.invalid(reason)
	return _request(path, method, args)


func _update(path: String, values: Dictionary, method: StringName) -> FirebaseTask:
	for key in values:
		if not key is String or not is_valid_path(key) or key.is_empty():
			return _requests.invalid("child path must be a non-empty valid path: %s" % str(key))
		var slash: int = key.find("/")
		while slash != -1:
			if values.has(key.left(slash)):
				return _requests.invalid("update paths must not contain both a parent and its child")
			slash = key.find("/", slash + 1)
		var reason := _validate_value(values[key], _path_depth(path) + _path_depth(key), [])
		if not reason.is_empty():
			return _requests.invalid(reason)
	return _request(path, method, [path, values])


static func _path_depth(path: String) -> int:
	return 0 if path.is_empty() else path.split("/").size()
