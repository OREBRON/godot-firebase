class_name FirebaseFirestore
extends RefCounted
## Cloud Firestore API.
##
## Document results are snapshots: {id, path, exists, data, metadata}.
## Metadata contains is_from_cache and has_pending_writes.
## Write success means server acknowledgement; local snapshots do not guarantee disk fsync.
## Filters are [field, op, value] arrays; op is one of FILTER_OPS.
## Order is [field, "asc" | "desc"] arrays.
## A cursor is a Dictionary with keys from CURSOR_KEYS: at most one start and one end, each
## an Array of values for the leading order_by fields ("__name__" takes the document ID).

const FILTER_OPS: Array[String] = ["==", "!=", "<", "<=", ">", ">=", "array-contains", "array-contains-any", "in", "not-in"]
const CURSOR_KEYS: Array[String] = ["start_at", "start_after", "end_at", "end_before"]
const MAX_LIMIT := 2147483647
const INVALID_DOCUMENT_ID := "document ID must be a non-empty string without '/'"

var _requests: FirebaseRequests
var _listeners: Dictionary[int, Callable] = {}


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.document_changed.connect(_on_snapshot)
		_requests.backend.query_changed.connect(_on_snapshot)


## Source is default (server with cache fallback), cache, or server.
func get_doc(path: String, source: String = "default") -> FirebaseTask:
	if not source in ["default", "cache", "server"]:
		return _invalid("source must be default, cache, or server")
	return _document_request(path, &"get_doc", [path, source])


## Replaces the document. With `merge`, only the given fields change.
func set_doc(path: String, data: Dictionary, merge := false) -> FirebaseTask:
	return _write(path, &"set_doc", FirebaseValue.validate_data(data, merge), [path, data, merge])


## Changes fields of an existing document. Keys may be dotted field paths.
func update_doc(path: String, data: Dictionary) -> FirebaseTask:
	return _write(path, &"update_doc", FirebaseValue.validate_update_data(data), [path, data])


func delete_doc(path: String) -> FirebaseTask:
	return _document_request(path, &"delete_doc", [path])


## Result value is an Array of snapshots. `limit` <= 0 means no limit; at most MAX_LIMIT.
## For the next page pass the last document's order_by values: {start_after = [...]}.
func query(collection_path: String, filters: Array = [], order_by: Array = [], limit: int = 0, source: String = "default", cursor: Dictionary = {}) -> FirebaseTask:
	return _query(&"run_query", collection_path, filters, order_by, limit, source, cursor)


## Returns {documents: Array, metadata: Dictionary}, including for empty results.
func query_snapshot(collection_path: String, filters: Array = [], order_by: Array = [], limit: int = 0, source: String = "default", cursor: Dictionary = {}) -> FirebaseTask:
	return _query(&"run_query_snapshot", collection_path, filters, order_by, limit, source, cursor)


## Result value is the number of documents matching `filters`, counted by the
## server without downloading them. Needs the network; local writes count once acknowledged.
func count(collection_path: String, filters: Array = []) -> FirebaseTask:
	var reason := _validate_query(collection_path, filters)
	if not reason.is_empty():
		return _invalid(reason)
	return _requests.send(&"run_count", [collection_path, filters])


## Completion acknowledges the SDK network command, not internet connectivity.
func set_network_enabled(enabled: bool) -> FirebaseTask:
	return _requests.send(&"set_network_enabled", [enabled])


## Waits for the current user's writes pending at this call. Later writes are
## excluded; changing user fails this barrier. It never cancels a pending write.
func wait_pending_writes() -> FirebaseTask:
	return _requests.send(&"wait_pending_writes")


func _query(method: StringName, collection_path: String, filters: Array, order_by: Array, limit: int, source: String, cursor: Dictionary) -> FirebaseTask:
	if not source in ["default", "cache", "server"]:
		return _invalid("source must be default, cache, or server")
	var reason := _validate_query(collection_path, filters, order_by, limit, cursor)
	if not reason.is_empty():
		return _invalid(reason)
	return _requests.send(method, [collection_path, filters, order_by, limit, source, cursor])


## Commits all writes atomically. Each op is a dictionary:
## {op = "set", path, data, merge = false} | {op = "update", path, data} | {op = "delete", path}
func batch(ops: Array) -> FirebaseTask:
	for op in ops:
		var reason := _validate_batch_op(op)
		if not reason.is_empty():
			return _invalid(reason)
	return _requests.send(&"commit_batch", [ops])


## Calls `callback(result: FirebaseResult)` with a snapshot now and after every change.
## A failed result is the last one: the listener is already removed when it arrives.
## Returns an id for remove_listener(), or 0 when the listener could not start.
func listen_doc(path: String, callback: Callable, include_metadata_changes: bool = false) -> int:
	if _requests.backend == null or not FirebaseValue.is_document_path(path):
		push_error("Firebase: cannot listen to %s" % path)
		return 0
	return _listen(_requests.backend.listen_doc(path, include_metadata_changes), callback)


## Like listen_doc() for a query: each result value is {documents, metadata} as
## query_snapshot() returns, sent now and whenever the matching documents change.
func listen_query(collection_path: String, callback: Callable, filters: Array = [], order_by: Array = [], limit: int = 0, cursor: Dictionary = {}, include_metadata_changes: bool = false) -> int:
	var reason := _validate_query(collection_path, filters, order_by, limit, cursor)
	if _requests.backend == null or not reason.is_empty():
		push_error("Firebase: cannot listen to %s: %s" % [collection_path, reason if reason else "no backend"])
		return 0
	return _listen(_requests.backend.listen_query(collection_path, filters, order_by, limit, cursor, include_metadata_changes), callback)


func _listen(id: int, callback: Callable) -> int:
	if id != 0:
		_listeners[id] = callback
	return id


func remove_listener(id: int) -> void:
	if _listeners.erase(id):
		_requests.backend.remove_listener(id)


func _document_request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not FirebaseValue.is_document_path(path):
		return _invalid("not a document path: %s" % path)
	return _requests.send(method, args)


## `reason` is the data validation result.
func _write(path: String, method: StringName, reason: String, args: Array) -> FirebaseTask:
	if not reason.is_empty():
		return _invalid(reason)
	return _document_request(path, method, args)


## Returns "" for a query the SDK accepts, otherwise the reason. The SDKs abort
## the process on most of these mistakes, so they never reach the backend.
static func _validate_query(collection_path: String, filters: Array, order_by: Array = [], limit: int = 0, cursor: Dictionary = {}) -> String:
	if not FirebaseValue.is_collection_path(collection_path):
		return "not a collection path: %s" % collection_path
	if limit > MAX_LIMIT:
		return "limit must be at most %d" % MAX_LIMIT
	var reason := _validate_filters(filters)
	if not reason.is_empty():
		return reason
	for order in order_by:
		if not order is Array or order.size() != 2 or not FirebaseValue.is_field_path(order[0]) or not order[1] in ["asc", "desc"]:
			return "order must be [field, \"asc\" | \"desc\"]: %s" % str(order)
	return _validate_cursor(cursor, order_by)


static func _validate_filters(filters: Array) -> String:
	var ops: Array[String] = []
	for filter in filters:
		if not filter is Array or filter.size() != 3 or not FirebaseValue.is_field_path(filter[0]) or not FILTER_OPS.has(filter[1]):
			return "filter must be [field, op, value] with op in %s: %s" % [FILTER_OPS, str(filter)]
		ops.append(String(filter[1]))
		var reason := FirebaseValue.validate_filter_value(filter[1], filter[2])
		if reason.is_empty() and filter[0] == "__name__":
			reason = _validate_document_id_filter(filter[1], filter[2])
		if not reason.is_empty():
			return reason
	# Query.conflictingOps() of the SDKs.
	for op in ["!=", "not-in"]:
		if ops.count(op) > 1:
			return "a query supports only one %s filter" % op
	if ops.has("not-in") and (ops.has("!=") or ops.has("in") or ops.has("array-contains-any")):
		return "not-in cannot be combined with !=, in or array-contains-any"
	return ""


static func _validate_document_id_filter(op: String, value: Variant) -> String:
	if op.begins_with("array-contains"):
		return "document IDs cannot use %s" % op
	var ids: Array = value if op in ["in", "not-in"] else [value]
	for id in ids:
		if not _is_document_id(id):
			return INVALID_DOCUMENT_ID
	return ""


## Each cursor value is a query value for the order_by field at its position.
static func _validate_cursor(cursor: Dictionary, order_by: Array) -> String:
	if cursor.has("start_at") and cursor.has("start_after") or cursor.has("end_at") and cursor.has("end_before"):
		return "a cursor has at most one start (start_at, start_after) and one end (end_at, end_before)"
	for key in cursor:
		if not (key is String or key is StringName) or not CURSOR_KEYS.has(key):
			return "cursor keys must be in %s: %s" % [CURSOR_KEYS, str(key)]
		var values: Variant = cursor[key]
		if not values is Array or values.is_empty() or values.size() > order_by.size():
			return "%s needs an Array with a value for each leading order_by field (order_by has %d)" % [key, order_by.size()]
		for index in values.size():
			var reason := FirebaseValue.validate_filter_value("==", values[index])
			if reason.is_empty() and order_by[index][0] == "__name__" and not _is_document_id(values[index]):
				reason = INVALID_DOCUMENT_ID
			if not reason.is_empty():
				return "%s: %s" % [key, reason]
	return ""


static func _is_document_id(id: Variant) -> bool:
	return (id is String or id is StringName) and not String(id).is_empty() and not String(id).contains("/")


func _validate_batch_op(op: Variant) -> String:
	if not op is Dictionary:
		return "batch op must be a dictionary: %s" % str(op)
	var path: Variant = op.get("path")
	if not (path is String or path is StringName) or not FirebaseValue.is_document_path(path):
		return "batch op needs a document path: %s" % str(op)
	var kind: Variant = op.get("op")
	if not (kind is String or kind is StringName) or not kind in ["set", "update", "delete"]:
		return "unknown batch op: %s" % str(kind)
	if kind == "delete":
		return ""
	var data: Variant = op.get("data")
	if not data is Dictionary:
		return "batch %s needs data" % kind
	if kind == "update":
		return FirebaseValue.validate_update_data(data)
	var merge: Variant = op.get("merge", false)
	if not merge is bool:
		return "batch merge must be a bool: %s" % str(merge)
	return FirebaseValue.validate_data(data, merge)


func _invalid(reason: String) -> FirebaseTask:
	return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)


func _on_snapshot(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String) -> void:
	var callback: Callable = _listeners.get(listener_id, Callable())
	# The SDK stops a listener after an error; a freed callback object never calls remove_listener().
	if not ok or not callback.is_valid():
		remove_listener(listener_id)
	if callback.is_valid():
		callback.call(FirebaseResult.success(snapshot) if ok else FirebaseResult.failure(error_code, error_message))
