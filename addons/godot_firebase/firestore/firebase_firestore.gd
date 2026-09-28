class_name FirebaseFirestore
extends RefCounted
## Cloud Firestore API.
##
## Document results are snapshots: {id, path, exists, data}.
## Filters are [field, op, value] arrays; op is one of FILTER_OPS.
## Order is [field, "asc" | "desc"] arrays.

const FILTER_OPS: Array[String] = ["==", "!=", "<", "<=", ">", ">=", "array-contains", "in"]

var _requests: FirebaseRequests
var _listeners: Dictionary[int, Callable] = {}


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.document_changed.connect(_on_document_changed)


func get_doc(path: String) -> FirebaseTask:
	return _document_request(path, &"get_doc", [path])


## Replaces the document. With `merge`, only the given fields change.
func set_doc(path: String, data: Dictionary, merge := false) -> FirebaseTask:
	return _write(path, &"set_doc", data, merge, [path, data, merge])


## Changes fields of an existing document. Keys may be dotted field paths.
func update_doc(path: String, data: Dictionary) -> FirebaseTask:
	return _write(path, &"update_doc", data, true, [path, data])


func delete_doc(path: String) -> FirebaseTask:
	return _document_request(path, &"delete_doc", [path])


## Result value is an Array of snapshots. `limit` <= 0 means no limit.
func query(collection_path: String, filters: Array = [], order_by: Array = [], limit := 0) -> FirebaseTask:
	if not FirebaseValue.is_collection_path(collection_path):
		return _invalid("not a collection path: %s" % collection_path)
	var reason := _validate_query(filters, order_by)
	if not reason.is_empty():
		return _invalid(reason)
	return _requests.send(&"run_query", [collection_path, filters, order_by, limit])


## Commits all writes atomically. Each op is a dictionary:
## {op = "set", path, data, merge = false} | {op = "update", path, data} | {op = "delete", path}
func batch(ops: Array) -> FirebaseTask:
	for op in ops:
		var reason := _validate_batch_op(op)
		if not reason.is_empty():
			return _invalid(reason)
	return _requests.send(&"commit_batch", [ops])


## Calls `callback(result: FirebaseResult)` with a snapshot now and after every change.
## Returns an id for remove_listener(), or 0 when the listener could not start.
func listen_doc(path: String, callback: Callable) -> int:
	if _requests.backend == null or not FirebaseValue.is_document_path(path):
		push_error("Firebase: cannot listen to %s" % path)
		return 0
	var id: int = _requests.backend.listen_doc(path)
	_listeners[id] = callback
	return id


func remove_listener(id: int) -> void:
	if _listeners.erase(id):
		_requests.backend.remove_listener(id)


func _document_request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not FirebaseValue.is_document_path(path):
		return _invalid("not a document path: %s" % path)
	return _requests.send(method, args)


func _write(path: String, method: StringName, data: Dictionary, allow_delete: bool, args: Array) -> FirebaseTask:
	var reason := FirebaseValue.validate_data(data, allow_delete)
	if not reason.is_empty():
		return _invalid(reason)
	return _document_request(path, method, args)


func _validate_query(filters: Array, order_by: Array) -> String:
	for filter in filters:
		if not filter is Array or filter.size() != 3 or not filter[0] is String or not FILTER_OPS.has(filter[1]):
			return "filter must be [field, op, value] with op in %s: %s" % [FILTER_OPS, str(filter)]
		var reason := FirebaseValue.validate_filter_value(filter[1], filter[2])
		if not reason.is_empty():
			return reason
	for order in order_by:
		if not order is Array or order.size() != 2 or not order[0] is String or not order[1] in ["asc", "desc"]:
			return "order must be [field, \"asc\" | \"desc\"]: %s" % str(order)
	return ""


func _validate_batch_op(op: Variant) -> String:
	if not op is Dictionary or not FirebaseValue.is_document_path(op.get("path", "")):
		return "batch op needs a document path: %s" % str(op)
	match op.get("op"):
		"delete":
			return ""
		"set", "update":
			var data: Variant = op.get("data")
			if not data is Dictionary:
				return "batch %s needs data" % op.op
			return FirebaseValue.validate_data(data, op.op == "update" or op.get("merge", false))
	return "unknown batch op: %s" % str(op.get("op"))


func _invalid(reason: String) -> FirebaseTask:
	return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)


func _on_document_changed(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String) -> void:
	var callback: Callable = _listeners.get(listener_id, Callable())
	if callback.is_valid():
		callback.call(FirebaseResult.success(snapshot) if ok else FirebaseResult.failure(error_code, error_message))
