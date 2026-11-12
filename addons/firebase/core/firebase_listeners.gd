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


## Returns `id`; 0 means the backend did not start the listener.
func add(id: int, callback: Callable) -> int:
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
