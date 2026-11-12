class_name FirebaseDatabaseMock
extends FirebaseMockModule
## In-memory FirebaseDatabaseNative. Nothing is persisted.

signal value_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)
signal children_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)

## The whole database value. Empty containers and null descendants are absent.
var root: Variant = null
## Path of every value and child listener.
var _listeners: Dictionary[int, String] = {}
var _queries: Dictionary[int, Dictionary] = {}
## Last snapshot sent to each value listener; the SDKs raise value events only on change.
var _sent: Dictionary[int, Dictionary] = {}
## Children each child listener reported last, in query order.
var _children_sent: Dictionary[int, Dictionary] = {}
var _push_count := 0
## Test-observable startup options. The mock does not persist to disk or
## connect to an emulator.
var persistence_enabled := false
var emulator_host := ""
var network_enabled := true
var _initialized := false
var _reference_used := false
## Test fixture state set by simulate_connection().
var _server_reachable := true
## Like the SDKs, the connection opens shortly after the first reference.
var _connected := false
## Unknown until the first connection, like .info/serverTimeOffset on devices.
var _server_time_offset: Variant = null
var _server_root: Variant = null
var _pending_reads: Array[Dictionary] = []
var _pending_writes: Array[Dictionary] = []
var _pending_registrations: Array[Dictionary] = []
var _disconnect_actions: Dictionary[String, Variant] = {}
## With persistence, the [path, query] pairs this client loaded or wrote; the SDKs keep them on disk.
var _disk_cache: Array = []


func initialize(persistence_enabled: bool = false, emulator_host: String = "") -> int:
	if _initialized or _reference_used:
		return ERR_ALREADY_IN_USE
	self.persistence_enabled = persistence_enabled
	self.emulator_host = emulator_host
	_initialized = true
	return OK


## Like the SDKs' single value listener: without a connection, a read waits for one
## unless the local cache holds the value.
func get_value(path: String, query: Dictionary) -> int:
	_use_reference()
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if _connected or path in FirebaseDatabase.INFO_PATHS or _is_cached(path, query):
		_read(id, path, query)
	else:
		_pending_reads.append({"id": id, "path": path, "query": query.duplicate(true)})
	return id


func _read(id: int, path: String, query: Dictionary) -> void:
	_keep_on_disk([path], query)
	_finish(id, _snapshot(path, query))


## Pending writes and active listeners hold values locally; with persistence the disk cache too.
func _is_cached(path: String, query: Dictionary) -> bool:
	var held := _disk_cache.duplicate()
	for id in _listeners:
		held.append([_listeners[id], _queries[id]])
	for write in _pending_writes:
		for change in write.changes:
			held.append([change.path, {}])
	return held.any(func(entry: Array) -> bool: return entry == [path, query] or entry[1].is_empty() and _within(path, entry[0]))


func _keep_on_disk(paths: Array, query: Dictionary = {}) -> void:
	if not persistence_enabled:
		return
	for path in paths:
		if not [path, query] in _disk_cache:
			_disk_cache.append([path, query.duplicate(true)])


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


## The SDKs create the connection with the first reference; it opens shortly after.
func _use_reference() -> void:
	if not _reference_used:
		_reference_used = true
		_update_connection.call_deferred()


func _update_connection() -> void:
	var open := network_enabled and _server_reachable
	if open == _connected:
		return
	_connected = open
	if open:
		_server_time_offset = 0
	for listener_id in _listeners:
		if _listeners[listener_id] in FirebaseDatabase.INFO_PATHS:
			_notify(listener_id)
	if open:
		_flush_offline_work()
	else:
		_run_disconnect_actions()


## Like the SDKs' restoreState(): queued reads, writes, then registrations, in order.
func _flush_offline_work() -> void:
	for read in _pending_reads:
		_read(read.id, read.path, read.query)
	_pending_reads.clear()
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
	var paths := actions.map(func(action): return action.path)
	_keep_on_disk(paths)
	_notify_changed(paths)


func _register_disconnect(registration: Dictionary) -> int:
	_use_reference()
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
	elif value is Dictionary and not value.has(".sv"):
		for key in value:
			_keep_uncancelled(_join(path, key), value[key], cancelled)
	elif value is Array:
		for index in value.size():
			_keep_uncancelled(_join(path, str(index)), value[index], cancelled)
	else:
		_disconnect_actions[path] = value


func listen_value(path: String, query: Dictionary) -> int:
	return _listen(value_changed, path, query)


func listen_children(path: String, query: Dictionary) -> int:
	return _listen(children_changed, path, query)


func _listen(changed: Signal, path: String, query: Dictionary) -> int:
	_use_reference()
	var id := _take_id()
	if _fail_listener_if_requested(changed, id):
		return id
	_listeners[id] = path
	_queries[id] = query.duplicate(true)
	if changed == children_changed:
		_children_sent[id] = {}
	_keep_on_disk([path], query)
	_notify(id)
	return id


func remove_listener(id: int) -> void:
	_listeners.erase(id)
	_queries.erase(id)
	_sent.erase(id)
	_children_sent.erase(id)


## Local snapshots update immediately; write completion models a server ACK.
func _write(changes: Array, result: Variant = null) -> int:
	_use_reference()
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	root = _apply_changes(root, changes)
	if _connected:
		_server_root = _copy(root)
		_finish(id, result)
	else:
		_pending_writes.append({"id": id, "changes": changes, "result": result})
	var paths := changes.map(func(change): return change.path)
	_keep_on_disk(paths)
	_notify_changed(paths)
	return id


func _notify_changed(changed_paths: Array) -> void:
	for listener_id in _listeners:
		if not _listeners[listener_id] in FirebaseDatabase.INFO_PATHS and changed_paths.any(func(changed): return _related(_listeners[listener_id], changed)):
			_notify(listener_id)


func _apply_changes(value: Variant, changes: Array) -> Variant:
	for change in changes:
		value = _store_at(value, _keys(change.path), 0, _resolve(change.value, _value_at(value, change.path)))
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


## `existing` is the stored value that `value` replaces; an increment adds to it.
func _resolve(value: Variant, existing: Variant) -> Variant:
	if value is Dictionary:
		if value == FirebaseDatabase.SERVER_TIMESTAMP:
			return int(Time.get_unix_time_from_system() * 1000)
		if value.has(".sv"):
			var by: Variant = value[".sv"].increment
			return existing + by if existing is int or existing is float else by
		var copy := {}
		for key in value:
			var child: Variant = _resolve(value[key], _child(existing, key))
			if child != null:
				copy[key] = child
		return null if copy.is_empty() else copy
	if value is StringName:
		return String(value)
	if value is Array or typeof(value) >= TYPE_PACKED_INT32_ARRAY and typeof(value) <= TYPE_PACKED_STRING_ARRAY:
		var items := []
		for index in value.size():
			items.append(_resolve(value[index], _child(existing, str(index))))
		while not items.is_empty() and items.back() == null:
			items.pop_back()
		return null if items.is_empty() else items
	return value


func _snapshot(path: String, query: Dictionary) -> Dictionary:
	if path in FirebaseDatabase.INFO_PATHS:
		var info: Variant = _connected if path == ".info/connected" else _server_time_offset
		return {"key": path.get_file(), "exists": info != null, "value": info}
	var value: Variant = _value_at(root, path)
	value = _delivered(value) if query.is_empty() else _query(value, query)
	return {"key": path.get_file(), "exists": value != null, "value": value}


static func _value_at(value: Variant, path: String) -> Variant:
	for key in _keys(path):
		value = _child(value, key)
	return value


## The children of `value` that match `query`, in query order, like a query snapshot.
func _query(value: Variant, query: Dictionary) -> Variant:
	var children := _children(value)
	if children.is_empty():
		# The SDKs keep a leaf for a bare order_by; filters and limits leave nothing.
		return value if query.size() == 1 else null
	var order: String = query.order_by
	var compare := _compare_keys if order == "$key" else _compare_values
	var entries: Array = []
	for key: String in children:
		var by: Variant = _sort_value(key, children[key], order)
		if (not query.has("start_at") or compare.call(by, query.start_at) >= 0) \
				and (not query.has("end_at") or compare.call(by, query.end_at) <= 0) \
				and (not query.has("equal_to") or compare.call(by, query.equal_to) == 0):
			entries.append([by, key])
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		var order_compared: int = compare.call(a[0], b[0])
		return order_compared < 0 or order_compared == 0 and _compare_keys(a[1], b[1]) < 0)
	if query.has("limit_to_first"):
		entries = entries.slice(0, query.limit_to_first)
	if query.has("limit_to_last"):
		entries = entries.slice(maxi(0, entries.size() - query.limit_to_last))
	var matched := {}
	for entry in entries:
		matched[entry[1]] = _delivered(children[entry[1]])
	return null if matched.is_empty() else matched


## What `order` sorts child `key` with value `value` by.
static func _sort_value(key: String, value: Variant, order: String) -> Variant:
	if order == "$key":
		return key
	return value if order == "$value" else _value_at(value, order)


## Realtime Database order: null, false, true, numbers, Strings, then maps and lists.
static func _compare_values(a: Variant, b: Variant) -> int:
	var rank_a := _rank(a)
	var rank_b := _rank(b)
	if rank_a != rank_b:
		return rank_a - rank_b
	if a is int or a is float or a is String:
		return 0 if a == b else -1 if a < b else 1
	return 0


static func _rank(value: Variant) -> int:
	if value is bool:
		return 2 if value else 1
	if value is int or value is float:
		return 3
	if value is String:
		return 4
	return 0 if value == null else 5


## Keys that are 32-bit integers come first, in numeric order, then the others as Strings.
static func _compare_keys(a: String, b: String) -> int:
	var int_a := _is_int_key(a)
	var int_b := _is_int_key(b)
	if int_a and int_b:
		return signi(a.to_int() - b.to_int())
	if int_a or int_b:
		return -1 if int_a else 1
	return 0 if a == b else -1 if a < b else 1


static func _is_int_key(key: String) -> bool:
	if key.length() > 11 or not key.is_valid_int():
		return false
	var number := key.to_int()
	return str(number) == key and number >= -2147483648 and number <= 2147483647


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
	if not _listeners.has(listener_id):
		return
	if _children_sent.has(listener_id):
		_notify_children(listener_id)
		return
	var snapshot := _snapshot(_listeners[listener_id], _queries[listener_id])
	if _sent.has(listener_id) and _sent[listener_id] == snapshot:
		return
	_sent[listener_id] = snapshot.duplicate(true)
	_deliver.call_deferred(value_changed, listener_id, snapshot)


## Like the SDKs' EventGenerator: "removed" children in their old order, then "added",
## "moved" and "changed" ones, each in the new order with the key of the child before it.
func _notify_children(listener_id: int) -> void:
	var before := _children_sent[listener_id]
	var query := _queries[listener_id]
	var after := _ordered_children(_listeners[listener_id], query)
	_children_sent[listener_id] = after
	var events: Array[Dictionary] = []
	for key: String in before:
		if not after.has(key):
			events.append({"event": "removed", "key": key, "value": before[key], "previous_key": null})
	var keys := after.keys()
	for event in ["added", "moved", "changed"]:
		for index in keys.size():
			if _raises(event, keys[index], before, after, query.get("order_by", "$key")):
				events.append({"event": event, "key": keys[index], "value": after[keys[index]], "previous_key": keys[index - 1] if index > 0 else null})
	for event in events:
		_deliver.call_deferred(children_changed, listener_id, event)


## The children of `path` that `query` matches, in its order; without a query, in key
## order, which is the SDKs' priority order when no child has a priority.
func _ordered_children(path: String, query: Dictionary) -> Dictionary:
	var children: Variant = _query(_value_at(root, path), query if query else {"order_by": "$key"})
	return children if children is Dictionary else {}


## Whether child `key` raises `event` between the two reports. Like Android's
## Index.indexedValueChanged(), a child moves when its sort value compares differently.
static func _raises(event: String, key: String, before: Dictionary, after: Dictionary, order: String) -> bool:
	if not before.has(key):
		return event == "added"
	if event == "moved":
		return _compare_values(_sort_value(key, before[key], order), _sort_value(key, after[key], order)) != 0
	# GDScript cannot compare values of different types with !=.
	return event == "changed" and (typeof(before[key]) != typeof(after[key]) or before[key] != after[key])


func _deliver(changed: Signal, listener_id: int, snapshot: Dictionary) -> void:
	if _listeners.has(listener_id):
		changed.emit(listener_id, true, snapshot, 0, "")


## A change at `changed` is visible to a listener on `listened` when one contains the other.
static func _related(listened: String, changed: String) -> bool:
	return _within(listened, changed) or _within(changed, listened)


## Whether `path` is `ancestor` or below it.
static func _within(path: String, ancestor: String) -> bool:
	return ancestor.is_empty() or (path + "/").begins_with(ancestor + "/")


static func _join(path: String, child: String) -> String:
	return child if path.is_empty() else path + "/" + child


static func _keys(path: String) -> PackedStringArray:
	return PackedStringArray() if path.is_empty() else path.split("/")
