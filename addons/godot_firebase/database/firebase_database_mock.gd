class_name FirebaseDatabaseMock
extends FirebaseMockModule
## In-memory FirebaseDatabaseNative. Nothing is persisted.

signal value_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)

## The whole database as nested dictionaries.
var root: Dictionary = {}
var _listeners: Dictionary[int, String] = {}
var _push_count := 0


func get_value(path: String) -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, _snapshot(path))
	return id


func set_value(path: String, value: Variant) -> int:
	return _write(func(): _store(path, value), [path])


func update_children(path: String, values: Dictionary) -> int:
	var changed: Array = values.keys().map(func(child): return _join(path, child))
	return _write(func():
		for child in values:
			_store(_join(path, child), values[child]), changed)


func remove_value(path: String) -> int:
	return set_value(path, null)


func push_value(path: String, value: Variant) -> int:
	_push_count += 1
	var key := "-mock%012d" % _push_count
	return _write(func(): _store(_join(path, key), value), [_join(path, key)], key)


func listen_value(path: String) -> int:
	var id := _take_id()
	_listeners[id] = path
	_notify.call_deferred(id)
	return id


func remove_listener(id: int) -> void:
	_listeners.erase(id)


## Applies a change, answers with `result` and notifies affected listeners.
func _write(apply: Callable, changed_paths: Array, result: Variant = null) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	apply.call()
	_finish(id, result)
	for listener_id in _listeners:
		if changed_paths.any(func(changed): return _related(_listeners[listener_id], changed)):
			_notify.call_deferred(listener_id)
	return id


func _store(path: String, value: Variant) -> void:
	var keys := _keys(path)
	if keys.is_empty():
		root = _resolve(value) if value is Dictionary else {}
		return
	var parent := root
	for key in keys.slice(0, -1):
		if not parent.get(key) is Dictionary:
			parent[key] = {}
		parent = parent[key]
	if value == null:
		parent.erase(keys[-1])
	else:
		parent[keys[-1]] = _resolve(value)


func _resolve(value: Variant) -> Variant:
	if value is Dictionary:
		if value == FirebaseDatabase.SERVER_TIMESTAMP:
			return int(Time.get_unix_time_from_system() * 1000)
		var copy := {}
		for key in value:
			copy[key] = _resolve(value[key])
		return copy
	if value is StringName:
		return String(value)
	if value is Array or typeof(value) >= TYPE_PACKED_INT32_ARRAY and typeof(value) <= TYPE_PACKED_STRING_ARRAY:
		return Array(value).map(_resolve)
	return value


func _snapshot(path: String) -> Dictionary:
	var value: Variant = root
	for key in _keys(path):
		value = value.get(key) if value is Dictionary else null
	if value is Dictionary and value.is_empty():
		value = null
	return {"key": path.get_file(), "exists": value != null, "value": value.duplicate(true) if value is Dictionary or value is Array else value}


func _notify(listener_id: int) -> void:
	if _listeners.has(listener_id):
		value_changed.emit(listener_id, true, _snapshot(_listeners[listener_id]), 0, "")


## A change at `changed` is visible to a listener on `listened` when one contains the other.
static func _related(listened: String, changed: String) -> bool:
	return listened.is_empty() or changed.is_empty() or (listened + "/").begins_with(changed + "/") or (changed + "/").begins_with(listened + "/")


static func _join(path: String, child: String) -> String:
	return child if path.is_empty() else path + "/" + child


static func _keys(path: String) -> PackedStringArray:
	return PackedStringArray() if path.is_empty() else path.split("/")
