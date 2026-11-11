class_name FirebaseFirestoreMock
extends FirebaseMockModule
## In-memory FirebaseFirestoreNative. Nothing is persisted.
## Queries follow the SDK's local matching and ordering (firebase-android-sdk
## core/Query.java, core/FieldFilter.java, core/Bound.java and model/Values.kt).

signal document_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)
signal query_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String)

## Firestore error code for a missing document on update.
const NOT_FOUND := 5
## Values.typeOrder() ranks of the value types this addon reads and writes.
enum TypeOrder { NULL_VALUE = 0, BOOLEAN = 2, NAN_VALUE = 3, NUMBER = 4, TIMESTAMP = 5, STRING = 8, BYTES = 9, REFERENCE = 11, GEO_POINT = 13, ARRAY = 14, MAP = 16 }
const KEY_FIELD := "__name__"
const INEQUALITY_OPS: Array[String] = ["<", "<=", ">", ">=", "!=", "not-in"]
# 2^63: the smallest double above every int64 value.
const INT64_BOUND := 9223372036854775808.0

var documents: Dictionary[String, Dictionary] = {}
var _listeners: Dictionary[int, Dictionary] = {}
var _cache_known: Dictionary[String, bool] = {}
var _server_documents: Dictionary[String, Dictionary] = {}
var _pending_writes: Array[Dictionary] = []
var _barriers: Dictionary[int, Array] = {}
var _network_enabled := true
var _auto_acknowledge := true
var _user_id := ""
## Test-observable startup option; the mock never connects to an emulator.
var emulator_host := ""


func initialize(emulator_host: String = "") -> int:
	self.emulator_host = emulator_host
	return OK


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


func run_query(collection_path: String, filters: Array, order_by: Array, limit: int, source: String = "default", cursor: Dictionary = {}) -> int:
	return _query(collection_path, filters, order_by, limit, source, cursor, false)


func run_query_snapshot(collection_path: String, filters: Array, order_by: Array, limit: int, source: String = "default", cursor: Dictionary = {}) -> int:
	return _query(collection_path, filters, order_by, limit, source, cursor, true)


## Counts on the server, like AggregateSource::kServer: acknowledged writes only.
func run_count(collection_path: String, filters: Array) -> int:
	var id := _take_id()
	if _fail_if_requested(id) or _fail_source(id, "server") or _fail_query(id, collection_path, filters):
		return id
	var ordering := _normalized_order_by(filters, [])
	var matching := _server_documents.keys().filter(func(path: String): return path.get_base_dir() == collection_path and _matches(path, _server_documents[path], filters, ordering, {}))
	_finish(id, matching.size())
	return id


func _query(collection_path: String, filters: Array, order_by: Array, limit: int, source: String, cursor: Dictionary, with_metadata: bool) -> int:
	var id := _take_id()
	if _fail_if_requested(id) or _fail_source(id, source) or _fail_query(id, collection_path, filters, order_by, limit, cursor):
		return id
	var result := _query_result(collection_path, filters, order_by, limit, cursor, source == "cache" or not _network_enabled)
	_finish(id, result if with_metadata else result.documents)
	return id


func _fail_query(id: int, collection_path: String, filters: Array, order_by: Array = [], limit: int = 0, cursor: Dictionary = {}) -> bool:
	var reason := FirebaseFirestore._validate_query(collection_path, filters, order_by, limit, cursor)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return not reason.is_empty()


## {documents, metadata} of a valid query over the local documents.
func _query_result(collection_path: String, filters: Array, order_by: Array, limit: int, cursor: Dictionary, from_cache: bool) -> Dictionary:
	var ordering := _normalized_order_by(filters, order_by)
	var matches: Array = []
	for path in documents:
		if path.get_base_dir() == collection_path and _matches(path, documents[path], filters, ordering, cursor):
			matches.append(_snapshot(path, from_cache))
	matches.sort_custom(func(a, b): return _compare_documents(a, b, ordering) < 0)
	if limit > 0:
		matches = matches.slice(0, limit)
	return {"documents": matches, "metadata": {"is_from_cache": from_cache, "has_pending_writes": matches.any(func(doc): return doc.metadata.has_pending_writes)}}


func _fail_source(id: int, source: String) -> bool:
	if not source in ["default", "cache", "server"]:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "source must be default, cache, or server")
		return true
	if source == "server" and not _network_enabled:
		_finish_error(id, 14, "Server is unavailable while the network is disabled")
		return true
	return false


func listen_doc(path: String, include_metadata_changes: bool = false) -> int:
	return _listen(document_changed, include_metadata_changes, func(from_cache: bool) -> Dictionary: return _snapshot(path, from_cache))


## Returns 0 for an invalid query, like the native backend.
func listen_query(collection_path: String, filters: Array, order_by: Array, limit: int, cursor: Dictionary = {}, include_metadata_changes: bool = false) -> int:
	if not FirebaseFirestore._validate_query(collection_path, filters, order_by, limit, cursor).is_empty():
		return 0
	# The SDK copies the query when the listener starts.
	filters = filters.duplicate(true)
	order_by = order_by.duplicate(true)
	cursor = cursor.duplicate(true)
	return _listen(query_changed, include_metadata_changes, func(from_cache: bool) -> Dictionary: return _query_result(collection_path, filters, order_by, limit, cursor, from_cache))


## `read(from_cache)` returns the listener's current result.
func _listen(changed: Signal, include_metadata_changes: bool, read: Callable) -> int:
	var id := _take_id()
	if _fail_listener_if_requested(changed, id):
		return id
	_listeners[id] = {"changed": changed, "read": read, "include_metadata_changes": include_metadata_changes, "last": {}}
	_notify(id)
	return id


func set_network_enabled(enabled: bool) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if _network_enabled != enabled:
		_network_enabled = enabled
		_notify_all()
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
		_notify_all()
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
	_notify_all()
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
	var staged_documents := documents.duplicate(true)
	var values: Dictionary = {}
	for op in ops:
		if op.op == "update" and not staged_documents.has(op.path):
			_finish_error(id, NOT_FOUND, "No document to update: %s" % op.path)
			return id
		_apply(op, staged_documents)
		values[op.path] = staged_documents[op.path].duplicate(true) if staged_documents.has(op.path) else null
	documents.assign(staged_documents)
	for path in values:
		_cache_known[path] = true
	_pending_writes.append({"id": id, "user_id": _user_id, "values": values})
	_notify_all()
	if _network_enabled and _auto_acknowledge:
		acknowledge_pending_writes.call_deferred()
	return id


func _apply(op: Dictionary, target_documents: Dictionary[String, Dictionary]) -> void:
	match op.op:
		"delete":
			target_documents.erase(op.path)
		"update":
			_write_fields(target_documents[op.path], op.data, true, false, target_documents[op.path])
		"set":
			var merge: bool = op.get("merge", false)
			var previous: Dictionary = target_documents.get(op.path, {})
			var target: Dictionary = previous if merge else {}
			_write_fields(target, op.data, false, merge, previous)
			target_documents[op.path] = target


## Update uses dotted field paths and replaces nested maps; merge-set merges them.
## Transforms read previous values even when the target replaces a document or map.
func _write_fields(target: Dictionary, data: Dictionary, dotted_keys: bool, merge_maps: bool, previous: Dictionary) -> void:
	for key in data:
		var parent := target
		var previous_parent := previous
		var segments: PackedStringArray = key.split(".") if dotted_keys else PackedStringArray([key])
		for segment in segments.slice(0, -1):
			var previous_child: Variant = previous_parent.get(segment)
			previous_parent = previous_child if previous_child is Dictionary else {}
			if not parent.get(segment) is Dictionary:
				parent[segment] = {}
			parent = parent[segment]
		_write_field(parent, segments[-1], data[key], merge_maps, previous_parent.get(segments[-1]))


func _write_field(parent: Dictionary, field: String, value: Variant, merge_maps: bool, previous: Variant) -> void:
	match FirebaseValue.tag_of(value):
		FirebaseValue.DELETE:
			parent.erase(field)
		FirebaseValue.SERVER_TIMESTAMP:
			parent[field] = FirebaseValue.timestamp(Time.get_unix_time_from_system())
		FirebaseValue.INCREMENT:
			parent[field] = (previous if previous is int or previous is float else 0) + value.by
		# ArrayTransformOperation: a missing or non-array previous value counts as [].
		FirebaseValue.ARRAY_UNION:
			var union: Array = previous.duplicate(true) if previous is Array else []
			for element in value.elements:
				if not _contains(union, element):
					union.append(_copy(element))
			parent[field] = union
		FirebaseValue.ARRAY_REMOVE:
			var kept: Array = previous if previous is Array else []
			parent[field] = kept.filter(func(item): return not _contains(value.elements, item)).map(_copy)
		"":
			if value is Dictionary:
				var nested: Dictionary = parent[field] if merge_maps and parent.get(field) is Dictionary else {}
				var previous_map: Dictionary = previous if previous is Dictionary else {}
				_write_fields(nested, value, false, merge_maps, previous_map)
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
	if field == KEY_FIELD:
		return {"found": true, "value": path.get_file()}
	var value: Variant = data
	for segment in field.split("."):
		if not value is Dictionary or not value.has(segment):
			return {"found": false, "value": null}
		value = value[segment]
	return {"found": true, "value": value}


## Query.getNormalizedOrderBy(): explicit orders, then the remaining inequality
## fields in field-path order, then the document ID; implicit orders take the
## last explicit direction.
func _normalized_order_by(filters: Array, order_by: Array) -> Array:
	var ordering: Array = order_by.map(func(order): return [String(order[0]), String(order[1])])
	var ordered: Array = ordering.map(func(order): return order[0])
	var direction: String = ordering[-1][1] if not ordering.is_empty() else "asc"
	var implicit_fields: Array = []
	for filter in filters:
		var field := String(filter[0])
		if INEQUALITY_OPS.has(String(filter[1])) and field != KEY_FIELD and not ordered.has(field) and not implicit_fields.has(field):
			implicit_fields.append(field)
	# FieldPath order compares dotted segments, not the joined string.
	implicit_fields.sort_custom(func(a, b): return _compare(Array(a.split(".")), Array(b.split("."))) < 0)
	for field in implicit_fields:
		ordering.append([field, direction])
	if not ordered.has(KEY_FIELD):
		ordering.append([KEY_FIELD, direction])
	return ordering


## Query.matches(): every ordered field exists (null counts), every filter matches
## and the document lies within the cursor.
func _matches(path: String, data: Dictionary, filters: Array, ordering: Array, cursor: Dictionary) -> bool:
	for order in ordering:
		if not _field(path, data, order[0]).found:
			return false
	for filter in filters:
		if not _matches_filter(_field(path, data, filter[0]), String(filter[1]), filter[2]):
			return false
	return _within_cursor(path, data, ordering, cursor)


## Bound.sortsBeforeDocument() and sortsAfterDocument(): *_at includes the position.
func _within_cursor(path: String, data: Dictionary, ordering: Array, cursor: Dictionary) -> bool:
	for key in cursor:
		var comparison := _compare_to_position(path, data, ordering, cursor[key])
		var inside: bool
		match String(key):
			"start_at": inside = comparison >= 0
			"start_after": inside = comparison > 0
			"end_at": inside = comparison <= 0
			_: inside = comparison < 0
		if not inside:
			return false
	return true


## Compares a document with cursor values for the leading order fields, in query order.
func _compare_to_position(path: String, data: Dictionary, ordering: Array, position: Array) -> int:
	for index in position.size():
		var result := _compare(_field(path, data, ordering[index][0]).value, position[index])
		if result != 0:
			return result if ordering[index][1] == "asc" else -result
	return 0


## Values.contains(), with the value equality this mock uses for "in".
func _contains(values: Array, value: Variant) -> bool:
	return values.any(func(item): return _compare(item, value) == 0)


## FieldFilter.matches() with the ArrayContains(Any)Filter and (Not)InFilter overrides.
func _matches_filter(field: Dictionary, op: String, expected: Variant) -> bool:
	if not field.found:
		return false
	var value: Variant = field.value
	match op:
		"array-contains":
			return _type_order(value) == TypeOrder.ARRAY and _contains(Array(value), expected)
		"array-contains-any":
			return _type_order(value) == TypeOrder.ARRAY and Array(value).any(func(item): return _contains(expected, item))
		"in":
			return _contains(expected, value)
		"not-in":
			# Neither a stored null nor a null in the list ever matches.
			return value != null and not expected.has(null) and not _contains(expected, value)
		"!=":
			# Types need not match, but a stored null never matches.
			return value != null and _compare(value, expected) != 0
	# Equality and ranges only match values of the filter value's type order.
	if _type_order(value) != _type_order(expected):
		return false
	var comparison := _compare(value, expected)
	match op:
		"==": return comparison == 0
		"<": return comparison < 0
		"<=": return comparison <= 0
		">": return comparison > 0
		">=": return comparison >= 0
	return false


## Query.comparator(): the normalized orders, which always end in a document-ID order.
func _compare_documents(a: Dictionary, b: Dictionary, ordering: Array) -> int:
	for order in ordering:
		var result := _compare(_field(a.path, a.data, order[0]).value, _field(b.path, b.data, order[0]).value)
		if result != 0:
			return result if order[1] == "asc" else -result
	return 0


## Values.typeOrder() for the Variant types that validation admits.
func _type_order(value: Variant) -> TypeOrder:
	match typeof(value):
		TYPE_NIL: return TypeOrder.NULL_VALUE
		TYPE_BOOL: return TypeOrder.BOOLEAN
		TYPE_INT: return TypeOrder.NUMBER
		TYPE_FLOAT: return TypeOrder.NAN_VALUE if is_nan(value) else TypeOrder.NUMBER
		TYPE_STRING, TYPE_STRING_NAME: return TypeOrder.STRING
		TYPE_PACKED_BYTE_ARRAY: return TypeOrder.BYTES
		TYPE_DICTIONARY:
			match FirebaseValue.tag_of(value):
				FirebaseValue.TIMESTAMP: return TypeOrder.TIMESTAMP
				FirebaseValue.REFERENCE: return TypeOrder.REFERENCE
				FirebaseValue.GEO_POINT: return TypeOrder.GEO_POINT
			return TypeOrder.MAP
	# Array and every packed array except PackedByteArray.
	return TypeOrder.ARRAY


## Values.compare(): the type order first, then the values within that type.
func _compare(a: Variant, b: Variant) -> int:
	var order := _type_order(a)
	if order != _type_order(b):
		return signi(order - _type_order(b))
	match order:
		TypeOrder.BOOLEAN: return _compare_scalars(int(a), int(b))
		TypeOrder.NUMBER: return _compare_numbers(a, b)
		TypeOrder.TIMESTAMP: return _compare_timestamps(a, b)
		# Godot compares Strings by code point, which is UTF-8 byte order.
		TypeOrder.STRING: return _compare_scalars(String(a), String(b))
		TypeOrder.BYTES, TypeOrder.ARRAY: return _compare_sequences(a, b)
		# Values.compareReferences(): path segments, then the segment count.
		TypeOrder.REFERENCE: return _compare_sequences(String(a.path).split("/"), String(b.path).split("/"))
		TypeOrder.GEO_POINT: return _compare_geo_points(a, b)
		TypeOrder.MAP: return _compare_maps(a, b)
	# Every null equals null and every NaN equals NaN.
	return 0


func _compare_scalars(a: Variant, b: Variant) -> int:
	return 0 if a == b else (-1 if a < b else 1)


## Values.compareNumbers(): exact for int64 against double, where GDScript rounds the int.
func _compare_numbers(a: Variant, b: Variant) -> int:
	if a is float and b is int:
		return _compare_float_with_int(a, b)
	if a is int and b is float:
		return -_compare_float_with_int(b, a)
	return _compare_scalars(a, b)


## NumberComparisonHelper.firestoreCompareDoubleWithLong() for a non-NaN double.
func _compare_float_with_int(value: float, integer: int) -> int:
	if value < -INT64_BOUND:
		return -1
	if value >= INT64_BOUND:
		return 1
	var truncated := int(value)
	if truncated != integer:
		return -1 if truncated < integer else 1
	return _compare_scalars(value, float(integer))


## Values.compareTimestamps(): seconds, then nanoseconds, without float rounding.
func _compare_timestamps(a: Dictionary, b: Dictionary) -> int:
	var result := _compare_scalars(a.get("seconds", 0), b.get("seconds", 0))
	return result if result != 0 else _compare_scalars(a.get("nanos", 0), b.get("nanos", 0))


## Values.compareGeoPoints(): latitude, then longitude.
func _compare_geo_points(a: Dictionary, b: Dictionary) -> int:
	var result := _compare_numbers(a.latitude, b.latitude)
	return result if result != 0 else _compare_numbers(a.longitude, b.longitude)


## Values.compareArrays() and compareBinaries() (unsigned bytes): elements, then length.
func _compare_sequences(a: Variant, b: Variant) -> int:
	for index in mini(a.size(), b.size()):
		var result := _compare(a[index], b[index])
		if result != 0:
			return result
	return signi(a.size() - b.size())


## Values.compareMaps(): sorted keys pairwise, key before value, then the field count.
func _compare_maps(a: Dictionary, b: Dictionary) -> int:
	var a_keys := a.keys()
	var b_keys := b.keys()
	a_keys.sort()
	b_keys.sort()
	for index in mini(a_keys.size(), b_keys.size()):
		var result := _compare_scalars(a_keys[index], b_keys[index])
		if result == 0:
			result = _compare(a[a_keys[index]], b[b_keys[index]])
		if result != 0:
			return result
	return signi(a_keys.size() - b_keys.size())


func _notify_all() -> void:
	for listener_id in _listeners:
		_notify(listener_id)


## Unchanged results are not sent again; metadata-only changes only with include_metadata_changes.
func _notify(listener_id: int) -> void:
	var listener: Dictionary = _listeners[listener_id]
	var snapshot: Dictionary = listener.read.call(not _network_enabled)
	var previous: Dictionary = listener.last
	listener.last = snapshot
	if not previous.is_empty() and _without_metadata(previous) == _without_metadata(snapshot):
		if not listener.include_metadata_changes or previous == snapshot:
			return
	_deliver_snapshot.call_deferred(listener_id, snapshot)


static func _without_metadata(snapshot: Dictionary) -> Array:
	if snapshot.has("documents"):
		return snapshot.documents.map(func(doc): return [doc.path, doc.data])
	return [snapshot.exists, snapshot.data]


func _deliver_snapshot(listener_id: int, snapshot: Dictionary) -> void:
	if _listeners.has(listener_id):
		_listeners[listener_id].changed.emit(listener_id, true, snapshot, 0, "")
