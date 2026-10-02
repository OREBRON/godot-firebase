class_name FirebaseFirestoreMock
extends FirebaseMockModule
## In-memory FirebaseFirestoreNative. Nothing is persisted.

signal document_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)

## Firestore error code for a missing document on update.
const NOT_FOUND := 5

var documents: Dictionary[String, Dictionary] = {}
var _listeners: Dictionary[int, Dictionary] = {}
var _cache_known: Dictionary[String, bool] = {}
var _server_documents: Dictionary[String, Dictionary] = {}
var _pending_writes: Array[Dictionary] = []
var _barriers: Dictionary[int, Array] = {}
var _network_enabled := true
var _auto_acknowledge := true
var _user_id := ""


func get_doc(path: String, source: String = "default") -> int:
	var id := _take_id()
	if _fail_if_requested(id) or _fail_source(id, source):
		return id
	var from_cache := source == "cache" or not _network_enabled
	if from_cache and not documents.has(path) and not _cache_known.has(path):
		_finish_error(id, 14, "Document is not available in the cache")
	else:
		_cache_known[path] = true
		_finish(id, _snapshot(path, from_cache))
	return id


func set_doc(path: String, data: Dictionary, merge: bool) -> int:
	return _commit([{"op": "set", "path": path, "data": data, "merge": merge}])


func update_doc(path: String, data: Dictionary) -> int:
	return _commit([{"op": "update", "path": path, "data": data}])


func delete_doc(path: String) -> int:
	return _commit([{"op": "delete", "path": path}])


func commit_batch(ops: Array) -> int:
	return _commit(ops)


func run_query(collection_path: String, filters: Array, order_by: Array, limit: int, source: String = "default") -> int:
	return _query(collection_path, filters, order_by, limit, source, false)


func run_query_snapshot(collection_path: String, filters: Array, order_by: Array, limit: int, source: String = "default") -> int:
	return _query(collection_path, filters, order_by, limit, source, true)


func _query(collection_path: String, filters: Array, order_by: Array, limit: int, source: String, with_metadata: bool) -> int:
	var id := _take_id()
	if _fail_if_requested(id) or _fail_source(id, source):
		return id
	if not FirebaseValue.is_collection_path(collection_path) or limit > FirebaseFirestore.MAX_LIMIT:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "invalid collection path or query limit")
		return id
	var reason := FirebaseFirestore._validate_query(filters, order_by)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
		return id
	var from_cache := source == "cache" or not _network_enabled
	var matches: Array = []
	for path in documents:
		if path.get_base_dir() == collection_path and _matches(path, documents[path], filters) and order_by.all(func(order): return _field(path, documents[path], order[0]).found):
			matches.append(_snapshot(path, from_cache))
	matches.sort_custom(func(a, b): return _ordered_before(a, b, order_by))
	if limit > 0:
		matches = matches.slice(0, limit)
	var metadata := {"is_from_cache": from_cache, "has_pending_writes": matches.any(func(doc): return doc.metadata.has_pending_writes)}
	_finish(id, {"documents": matches, "metadata": metadata} if with_metadata else matches)
	return id


func _fail_source(id: int, source: String) -> bool:
	if not source in ["default", "cache", "server"]:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "source must be default, cache, or server")
		return true
	if source == "server" and not _network_enabled:
		_finish_error(id, 14, "Server is unavailable while the network is disabled")
		return true
	return false


func listen_doc(path: String, include_metadata_changes: bool = false) -> int:
	var id := _take_id()
	_listeners[id] = {"path": path, "include_metadata_changes": include_metadata_changes, "last": {}}
	_notify(id)
	return id


func set_network_enabled(enabled: bool) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if _network_enabled != enabled:
		_network_enabled = enabled
		for listener_id in _listeners:
			_notify(listener_id)
	_finish(id)
	if enabled and _auto_acknowledge:
		acknowledge_pending_writes.call_deferred()
	return id


func wait_pending_writes() -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	_barriers[id] = _pending_writes.filter(func(write): return write.user_id == _user_id).map(func(write): return write.id)
	_finish_barriers()
	return id


## Test control: server ACKs are automatic while online unless explicitly paused.
func set_auto_acknowledge(enabled: bool) -> void:
	_auto_acknowledge = enabled


## Test control: acknowledge at most `count` active-user writes; negative means all.
func acknowledge_pending_writes(count: int = -1) -> void:
	if not _network_enabled:
		return
	var acknowledged := 0
	for write in _pending_writes.duplicate():
		if write.user_id != _user_id or count >= 0 and acknowledged >= count:
			continue
		_pending_writes.erase(write)
		# Save the already-resolved mutations, avoiding replay of transforms.
		for path in write.values:
			if write.values[path] == null:
				_server_documents.erase(path)
			else:
				_server_documents[path] = write.values[path].duplicate(true)
		_finish(write.id)
		acknowledged += 1
		for listener_id in _listeners:
			if write.values.has(_listeners[listener_id].path):
				_notify(listener_id)
	_finish_barriers()


## Test control only; mocks have no cross-module Auth dependency or disk persistence.
func simulate_user_change(user_id: String) -> void:
	if _user_id == user_id:
		return
	_user_id = user_id
	for id in _barriers:
		_finish_error(id, 1, "Pending-writes barrier cancelled because the user changed")
	_barriers.clear()
	documents = _server_documents.duplicate(true)
	for write in _pending_writes:
		if write.user_id == _user_id:
			for path in write.values:
				if write.values[path] == null:
					documents.erase(path)
				else:
					documents[path] = write.values[path].duplicate(true)
	for listener_id in _listeners:
		_notify(listener_id)
	if _network_enabled and _auto_acknowledge:
		acknowledge_pending_writes.call_deferred()


func _finish_barriers() -> void:
	var pending_ids: Array = _pending_writes.map(func(write): return write.id)
	for id in _barriers.keys():
		if not _barriers[id].any(func(write_id): return pending_ids.has(write_id)):
			_barriers.erase(id)
			_finish(id)


func remove_listener(id: int) -> void:
	_listeners.erase(id)


func _commit(ops: Array) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if ops.is_empty():
		_finish(id)
		return id
	for op in ops:
		if op.op == "update" and not documents.has(op.path):
			_finish_error(id, NOT_FOUND, "No document to update: %s" % op.path)
			return id
	var values: Dictionary = {}
	for op in ops:
		_apply(op)
		_cache_known[op.path] = true
		values[op.path] = documents[op.path].duplicate(true) if documents.has(op.path) else null
	_pending_writes.append({"id": id, "user_id": _user_id, "values": values})
	for listener_id in _listeners:
		if values.has(_listeners[listener_id].path):
			_notify(listener_id)
	if _network_enabled and _auto_acknowledge:
		acknowledge_pending_writes.call_deferred()
	return id


func _apply(op: Dictionary) -> void:
	match op.op:
		"delete":
			documents.erase(op.path)
		"update":
			_write_fields(documents[op.path], op.data, true, false)
		"set":
			var merge: bool = op.get("merge", false)
			var target: Dictionary = documents.get(op.path, {}) if merge else {}
			_write_fields(target, op.data, false, merge)
			documents[op.path] = target


## Update uses dotted field paths and replaces nested maps; merge-set merges them.
func _write_fields(target: Dictionary, data: Dictionary, dotted_keys: bool, merge_maps: bool) -> void:
	for key in data:
		var parent := target
		var segments: PackedStringArray = key.split(".") if dotted_keys else PackedStringArray([key])
		for segment in segments.slice(0, -1):
			if not parent.get(segment) is Dictionary:
				parent[segment] = {}
			parent = parent[segment]
		_write_field(parent, segments[-1], data[key], merge_maps)


func _write_field(parent: Dictionary, field: String, value: Variant, merge_maps: bool) -> void:
	match FirebaseValue.tag_of(value):
		FirebaseValue.DELETE:
			parent.erase(field)
		FirebaseValue.SERVER_TIMESTAMP:
			parent[field] = FirebaseValue.timestamp(Time.get_unix_time_from_system())
		FirebaseValue.INCREMENT:
			var current: Variant = parent.get(field)
			parent[field] = (current if current is int or current is float else 0) + value.by
		"":
			if value is Dictionary:
				var nested: Dictionary = parent[field] if merge_maps and parent.get(field) is Dictionary else {}
				_write_fields(nested, value, false, merge_maps)
				parent[field] = nested
			else:
				parent[field] = _copy(value)
		_:
			parent[field] = value.duplicate()


func _copy(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Dictionary:
		return value.duplicate(true)
	if value is Array or typeof(value) >= TYPE_PACKED_INT32_ARRAY and typeof(value) <= TYPE_PACKED_STRING_ARRAY:
		return Array(value).map(_copy)
	return value


func _snapshot(path: String, from_cache: bool = false) -> Dictionary:
	var exists := documents.has(path)
	var pending := _pending_writes.any(func(write): return write.user_id == _user_id and write.values.has(path))
	return {"id": path.get_file(), "path": path, "exists": exists, "data": documents[path].duplicate(true) if exists else {}, "metadata": {"is_from_cache": from_cache, "has_pending_writes": pending}}


## Resolves dotted paths without confusing a missing field with a stored null.
func _field(path: String, data: Dictionary, field: String) -> Dictionary:
	if field == "__name__":
		return {"found": true, "value": path.get_file()}
	var value: Variant = data
	for segment in field.split("."):
		if not value is Dictionary or not value.has(segment):
			return {"found": false, "value": null}
		value = value[segment]
	return {"found": true, "value": value}


func _matches(path: String, data: Dictionary, filters: Array) -> bool:
	for filter in filters:
		var field := _field(path, data, filter[0])
		if not field.found:
			return false
		var value: Variant = field.value
		var expected: Variant = filter[2]
		var passed: bool
		match filter[1]:
			"==": passed = _compare(value, expected) == 0
			"!=": passed = _compare(value, expected) != 0
			"<": passed = _compare(value, expected) < 0
			"<=": passed = _compare(value, expected) <= 0
			">": passed = _compare(value, expected) > 0
			">=": passed = _compare(value, expected) >= 0
			"array-contains": passed = value is Array and value.any(func(item): return _compare(item, expected) == 0)
			"in": passed = expected.any(func(item): return _compare(value, item) == 0)
		if not passed:
			return false
	return true


func _ordered_before(a: Dictionary, b: Dictionary, order_by: Array) -> bool:
	for order in order_by:
		var result := _compare(_field(a.path, a.data, order[0]).value, _field(b.path, b.data, order[0]).value)
		if result != 0:
			return result < 0 if order[1] == "asc" else result > 0
	# Firestore uses the document key as a stable final ordering.
	return a.path < b.path if order_by.is_empty() or order_by[-1][1] == "asc" else a.path > b.path


## Orders values of different types by type first, like Firestore does.
func _compare(a: Variant, b: Variant) -> int:
	var a_key: Variant = _sort_value(a)
	var b_key: Variant = _sort_value(b)
	var a_rank := _type_rank(a_key)
	var b_rank := _type_rank(b_key)
	if a_rank != b_rank:
		return signi(a_rank - b_rank)
	if a_rank >= 4:
		return 0 if a_key == b_key else 1
	return 0 if a_key == b_key else (-1 if a_key < b_key else 1)


func _sort_value(value: Variant) -> Variant:
	if FirebaseValue.tag_of(value) == FirebaseValue.TIMESTAMP:
		return FirebaseValue.to_unix_seconds(value)
	return String(value) if value is StringName else value


func _type_rank(value: Variant) -> int:
	match typeof(value):
		TYPE_NIL: return 0
		TYPE_BOOL: return 1
		TYPE_INT, TYPE_FLOAT: return 2
		TYPE_STRING: return 3
	return 4


func _notify(listener_id: int) -> void:
	if not _listeners.has(listener_id):
		return
	var listener: Dictionary = _listeners[listener_id]
	var snapshot := _snapshot(listener.path, not _network_enabled)
	var previous: Dictionary = listener.last
	listener.last = snapshot
	if not previous.is_empty() and previous.exists == snapshot.exists and previous.data == snapshot.data:
		if not listener.include_metadata_changes or previous.metadata == snapshot.metadata:
			return
	_deliver_snapshot.call_deferred(listener_id, snapshot)


func _deliver_snapshot(listener_id: int, snapshot: Dictionary) -> void:
	if _listeners.has(listener_id):
		document_changed.emit(listener_id, true, snapshot, 0, "")
