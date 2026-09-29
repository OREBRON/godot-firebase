class_name FirebaseRequests
extends RefCounted
## Sends requests to the backend and pairs its completion signal with tasks.
##
## A backend method returns a request id and later emits
## `request_completed(id, ok, value, error_code, error_message)`.

var backend: Object
var _pending: Dictionary[int, FirebaseTask] = {}


func _init(active_backend: Object) -> void:
	backend = active_backend
	if backend:
		backend.request_completed.connect(_on_request_completed)


func send(method: StringName, args: Array = []) -> FirebaseTask:
	if backend == null:
		return failed(FirebaseResult.ERR_UNAVAILABLE, "Firebase is not available on this build")
	var task := FirebaseTask.new()
	_pending[backend.callv(method, args)] = task
	return task


## Returns a task that fails on the next idle frame, so callers can always await it.
func failed(code: int, message: String) -> FirebaseTask:
	var task := FirebaseTask.new()
	task.finish.call_deferred(FirebaseResult.failure(code, message))
	return task


func _on_request_completed(id: int, ok: bool, value: Variant, error_code: int, error_message: String) -> void:
	var task: FirebaseTask = _pending.get(id)
	if task == null:
		return
	_pending.erase(id)
	task.finish(FirebaseResult.success(value) if ok else FirebaseResult.failure(error_code, error_message))
