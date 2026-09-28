class_name FirebaseFirestoreMock
extends FirebaseMockModule
## In-memory FirebaseFirestoreNative. Nothing is persisted.

signal document_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)

## Firestore error code for a missing document on update.
const NOT_FOUND := 5

var documents: Dictionary[String, Dictionary] = {}
var _listeners: Dictionary[int, String] = {}


func get_doc(path: String) -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, _snapshot(path))
	return id


func set_doc(path: String, data: Dictionary, merge: bool) -> int:
	return _commit([{"op": "set", "path": path, "data": data, "merge": merge}])


func update_doc(path: String, data: Dictionary) -> int:
	return _commit([{"op": "update", "path": path, "data": data}])


func delete_doc(path: String) -> int:
	return _commit([{"op": "delete", "path": path}])


func commit_batch(ops: Array) -> int:
	return _commit(ops)


func run_query(collection_path: String, filters: Array, order_by: Array, limit: int) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	var matches: Array = []
	for path in documents:
		if path.get_base_dir() == collection_path and _matches(documents[path], filters):
			matches.append(_snapshot(path))
	matches.sort_custom(func(a, b): return _ordered_before(a.data, b.data, order_by))
	_finish(id, matches.slice(0, limit) if limit > 0 else matches)
	return id


func listen_doc(path: String) -> int:
	var id := _take_id()
	_listeners[id] = path
	_notify.call_deferred(id)
	return id


func remove_listener(id: int) -> void:
	_listeners.erase(id)


func _commit(ops: Array) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	for op in ops:
		if op.op == "update" and not documents.has(op.path):
			_finish_error(id, NOT_FOUND, "No document to update: %s" % op.path)
			return id
	for op in ops:
		_apply(op)
	_finish(id)
	for listener_id in _listeners:
		if ops.any(func(op): return op.path == _listeners[listener_id]):
			_notify.call_deferred(listener_id)
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


func _snapshot(path: String) -> Dictionary:
	var exists := documents.has(path)
	return {"id": path.get_file(), "path": path, "exists": exists, "data": documents[path].duplicate(true) if exists else {}}


func _matches(data: Dictionary, filters: Array) -> bool:
	for filter in filters:
		if not data.has(filter[0]):
			return false
		var value: Variant = data[filter[0]]
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
		var result := _compare(a.get(order[0]), b.get(order[0]))
		if result != 0:
			return result < 0 if order[1] == "asc" else result > 0
	return false


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
	if _listeners.has(listener_id):
		document_changed.emit(listener_id, true, _snapshot(_listeners[listener_id]), 0, "")
