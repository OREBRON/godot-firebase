class_name FirebaseDatabaseMock
extends FirebaseMockModule
## In-memory FirebaseDatabaseNative. Nothing is persisted.

signal value_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)

## The whole database value. Empty containers and null descendants are absent.
var root: Variant = null
var _listeners: Dictionary[int, String] = {}
var _push_count := 0
## Test-observable startup option. The mock does not persist to disk.
var persistence_enabled := false
var network_enabled := true
var _initialized := false
var _reference_used := false
## Test fixture state set by simulate_connection().
var _server_reachable := true
var _connected := true
var _server_root: Variant = null
var _pending_writes: Array[Dictionary] = []
var _pending_registrations: Array[Dictionary] = []
var _disconnect_actions: Dictionary[String, Variant] = {}


func initialize(persistence_enabled: bool = false) -> int:
	if _initialized or _reference_used:
		return ERR_ALREADY_IN_USE
	self.persistence_enabled = persistence_enabled
	_initialized = true
	return OK


func get_value(path: String) -> int:
	_reference_used = true
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, _snapshot(path))
	return id


func set_value(path: String, value: Variant) -> int:
	return _write([{"path": path, "value": _copy(value)}])


func update_children(path: String, values: Dictionary) -> int:
	return _write(_child_changes(path, values))


func remove_value(path: String) -> int:
	return set_value(path, null)


func push_value(path: String, value: Variant) -> int:
	_push_count += 1
	var key := "-mock%012d" % _push_count
	return _write([{"path": _join(path, key), "value": _copy(value)}], key)


## Like GoOffline/GoOnline: going offline closes the connection at once; going
## online reconnects after this request completes, when the server is reachable.
func set_network_enabled(enabled: bool) -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		network_enabled = enabled
		_finish(id)
		if enabled:
			_update_connection.call_deferred()
		else:
			_update_connection()
	return id


func on_disconnect_set_value(path: String, value: Variant) -> int:
	return _register_disconnect({"changes": [{"path": path, "value": _copy(value)}]})


func on_disconnect_update_children(path: String, values: Dictionary) -> int:
	return _register_disconnect({"changes": _child_changes(path, values)})


func on_disconnect_remove_value(path: String) -> int:
	return on_disconnect_set_value(path, null)


func on_disconnect_cancel(path: String) -> int:
	return _register_disconnect({"cancel": path})


## Test fixture: models whether the server is reachable, independently of GoOnline.
## The connection is open while the server is reachable and the network is enabled.
func simulate_connection(connected: bool) -> void:
	_server_reachable = connected
	_update_connection()


func _update_connection() -> void:
	var open := network_enabled and _server_reachable
	if open == _connected:
		return
	_connected = open
	for listener_id in _listeners:
		if _listeners[listener_id] == ".info/connected":
			_notify(listener_id)
	if open:
		_flush_offline_work()
	else:
		_run_disconnect_actions()


## Like the SDKs' restoreState(): queued writes, then queued registrations, in order.
func _flush_offline_work() -> void:
	for write in _pending_writes:
		_server_root = _apply_changes(_server_root, write.changes)
		_finish(write.id, write.result)
	_pending_writes.clear()
	root = _copy(_server_root)
	_notify_changed([""])
	for registration in _pending_registrations:
		_accept_registration(registration)
	_pending_registrations.clear()


## The server runs the actions, and the SDKs apply them to the local cache at once.
func _run_disconnect_actions() -> void:
	var actions: Array = []
	for path in _disconnect_actions:
		actions.append({"path": path, "value": _disconnect_actions[path]})
	_disconnect_actions.clear()
	_server_root = _apply_changes(_server_root, actions)
	root = _copy(_server_root)
	_notify_changed(actions.map(func(action): return action.path))


func _register_disconnect(registration: Dictionary) -> int:
	_reference_used = true
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	registration.id = id
	if _connected:
		_accept_registration(registration)
	else:
		_pending_registrations.append(registration)
	return id


func _accept_registration(registration: Dictionary) -> void:
	if registration.has("cancel"):
		_cancel_actions(registration.cancel)
	else:
		for change in registration.changes:
			_remember_action(change.path, change.value)
	_finish(registration.id)


func _remember_action(path: String, value: Variant) -> void:
	for queued in _disconnect_actions.keys():
		if queued == path:
			_disconnect_actions[queued] = value
			return
		if queued.is_empty() or path.begins_with(queued + "/"):
			var relative := path if queued.is_empty() else path.substr(queued.length() + 1)
			_disconnect_actions[queued] = _store_at(_disconnect_actions[queued], _keys(relative), 0, value)
			return
	for queued in _disconnect_actions.keys():
		if path.is_empty() or queued.begins_with(path + "/"):
			_disconnect_actions.erase(queued)
	_disconnect_actions[path] = value


func _cancel_actions(path: String) -> void:
	for queued in _disconnect_actions.keys():
		if path.is_empty() or queued == path or queued.begins_with(path + "/"):
			_disconnect_actions.erase(queued)
		elif queued.is_empty() or path.begins_with(queued + "/"):
			var value: Variant = _disconnect_actions[queued]
			_disconnect_actions.erase(queued)
			_keep_uncancelled(queued, value, path)


func _keep_uncancelled(path: String, value: Variant, cancelled: String) -> void:
	if path == cancelled:
		return
	if not path.is_empty() and not cancelled.begins_with(path + "/"):
		_disconnect_actions[path] = value
	elif value is Dictionary and value != FirebaseDatabase.SERVER_TIMESTAMP:
		for key in value:
			_keep_uncancelled(_join(path, key), value[key], cancelled)
	elif value is Array:
		for index in value.size():
			_keep_uncancelled(_join(path, str(index)), value[index], cancelled)
	else:
		_disconnect_actions[path] = value


func listen_value(path: String) -> int:
	_reference_used = true
	var id := _take_id()
	_listeners[id] = path
	_notify(id)
	return id


func remove_listener(id: int) -> void:
	_listeners.erase(id)


## Local snapshots update immediately; write completion models a server ACK.
func _write(changes: Array, result: Variant = null) -> int:
	_reference_used = true
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	root = _apply_changes(root, changes)
	if _connected:
		_server_root = _copy(root)
		_finish(id, result)
	else:
		_pending_writes.append({"id": id, "changes": changes, "result": result})
	_notify_changed(changes.map(func(change): return change.path))
	return id


func _notify_changed(changed_paths: Array) -> void:
	for listener_id in _listeners:
		if not _listeners[listener_id] in FirebaseDatabase.INFO_PATHS and changed_paths.any(func(changed): return _related(_listeners[listener_id], changed)):
			_notify(listener_id)


func _apply_changes(value: Variant, changes: Array) -> Variant:
	for change in changes:
		value = _store_at(value, _keys(change.path), 0, _resolve(change.value))
	return value


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


static func _child_changes(path: String, values: Dictionary) -> Array:
	var changes: Array = []
	for child in values:
		changes.append({"path": _join(path, child), "value": _copy(values[child])})
	return changes


func _store_at(current: Variant, keys: PackedStringArray, index: int, value: Variant) -> Variant:
	if index == keys.size():
		return value
	var key := keys[index]
	var child: Variant = _child(current, key)
	var updated: Variant = _store_at(child, keys, index + 1, value)
	if updated == null and child == null:
		return current
	if current is Array and key.is_valid_int() and str(key.to_int()) == key:
		var position := key.to_int()
		if position >= 0 and position <= current.size():
			var items: Array = current.duplicate()
			if position == items.size():
				items.append(updated)
			else:
				items[position] = updated
			while not items.is_empty() and items.back() == null:
				items.pop_back()
			return null if items.is_empty() else items
	var children: Dictionary = current.duplicate() if current is Dictionary else {}
	if current is Array:
		for i in current.size():
			if current[i] != null:
				children[str(i)] = current[i]
	if updated == null:
		children.erase(key)
	else:
		children[key] = updated
	return null if children.is_empty() else children


static func _child(value: Variant, key: String) -> Variant:
	if value is Dictionary:
		return value.get(key)
	if value is Array and key.is_valid_int() and str(key.to_int()) == key:
		var index := key.to_int()
		return value[index] if index >= 0 and index < value.size() else null
	return null


func _resolve(value: Variant) -> Variant:
	if value is Dictionary:
		if value == FirebaseDatabase.SERVER_TIMESTAMP:
			return int(Time.get_unix_time_from_system() * 1000)
		var copy := {}
		for key in value:
			var child: Variant = _resolve(value[key])
			if child != null:
				copy[key] = child
		return null if copy.is_empty() else copy
	if value is StringName:
		return String(value)
	if value is Array or typeof(value) >= TYPE_PACKED_INT32_ARRAY and typeof(value) <= TYPE_PACKED_STRING_ARRAY:
		var items := Array(value).map(_resolve)
		while not items.is_empty() and items.back() == null:
			items.pop_back()
		return null if items.is_empty() else items
	return value


func _snapshot(path: String) -> Dictionary:
	if path in FirebaseDatabase.INFO_PATHS:
		return {"key": path.get_file(), "exists": true, "value": _connected if path == ".info/connected" else 0}
	var value: Variant = root
	for key in _keys(path):
		value = _child(value, key)
	return {"key": path.get_file(), "exists": value != null, "value": _delivered(value)}


## A copy of `value` as DataSnapshot::value() delivers it on iOS and Android. The SDKs'
## getValue()/valForExport: turn children whose keys are all list indexes into an Array,
## null in gaps, when the largest index is below twice the child count. Other maps
## pass through std::map, so their keys arrive in byte order.
static func _delivered(value: Variant) -> Variant:
	var children := _children(value)
	if children.is_empty():
		return value
	var keys := children.keys()
	keys.sort()
	var delivered := {}
	for key in keys:
		delivered[key] = _delivered(children[key])
	return _as_list(delivered)


## Child values by key; the mock keeps lists that were written as Arrays.
static func _children(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	var children := {}
	if value is Array:
		for index in value.size():
			if value[index] != null:
				children[str(index)] = value[index]
	return children


static func _as_list(children: Dictionary) -> Variant:
	var largest := 0
	for key: String in children:
		if not _is_list_index(key):
			return children
		largest = maxi(largest, key.to_int())
	if largest >= 2 * children.size():
		return children
	var items := []
	items.resize(largest + 1)
	for key: String in children:
		items[key.to_int()] = children[key]
	return items


## Digits without a leading zero. Longer keys could never pass the size rule.
static func _is_list_index(key: String) -> bool:
	return key.length() <= 10 and key.is_valid_int() and (key == "0" or key[0] in "123456789")


func _notify(listener_id: int) -> void:
	if _listeners.has(listener_id):
		_deliver_snapshot.call_deferred(listener_id, _snapshot(_listeners[listener_id]))


func _deliver_snapshot(listener_id: int, snapshot: Dictionary) -> void:
	if _listeners.has(listener_id):
		value_changed.emit(listener_id, true, snapshot, 0, "")


## A change at `changed` is visible to a listener on `listened` when one contains the other.
static func _related(listened: String, changed: String) -> bool:
	return listened.is_empty() or changed.is_empty() or (listened + "/").begins_with(changed + "/") or (changed + "/").begins_with(listened + "/")


static func _join(path: String, child: String) -> String:
	return child if path.is_empty() else path + "/" + child


static func _keys(path: String) -> PackedStringArray:
	return PackedStringArray() if path.is_empty() else path.split("/")
