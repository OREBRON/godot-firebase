class_name FirebaseListeners
extends RefCounted
## Callbacks of a module's snapshot listeners, by the listener id its backend returned.
##
## The backend emits `(listener_id, ok, snapshot, error_code, error_message)` for each
## event; connect that signal to deliver(). A failed event is the last one.

var _backend: Object
var _callbacks: Dictionary[int, Callable] = {}


func _init(backend: Object) -> void:
	_backend = backend


## Starts a listener on `path` with the backend's `method(args)` and keeps `callback`
## for its events. `reason` is the caller's validation result. Returns the listener
## id, or 0 when it could not start.
func start(path: String, reason: String, callback: Callable, method: StringName, args: Array) -> int:
	# A callback that can never be called must not subscribe natively.
	if _backend == null or not reason.is_empty() or not callback.is_valid():
		push_error("Firebase: cannot listen to %s: %s" % [path, reason if reason else "no backend or invalid callback"])
		return 0
	var id: int = _backend.callv(method, args)
	if id != 0:
		_callbacks[id] = callback
	return id


func remove(id: int) -> void:
	if _callbacks.erase(id):
		_backend.remove_listener(id)


func deliver(listener_id: int, ok: bool, snapshot: Dictionary, error_code: int, error_message: String) -> void:
	var callback: Callable = _callbacks.get(listener_id, Callable())
	# The SDK stops a listener after an error; a freed callback object never calls remove_listener().
	if not ok or not callback.is_valid():
		remove(listener_id)
	if callback.is_valid():
		callback.call(FirebaseResult.success(snapshot) if ok else FirebaseResult.failure(error_code, error_message))
