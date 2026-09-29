class_name FirebaseMockModule
extends RefCounted
## Shared part of the in-memory module backends used in the editor, on desktop
## and in tests. Answers arrive on the next idle frame, like native answers.

signal request_completed(id: int, ok: bool, value: Variant, error_code: int, error_message: String)

var _next_id := 0
var _next_failure: Array = []


func initialize() -> int:
	return OK


## Makes the next request fail with this code and message.
func fail_next(code: int, message: String) -> void:
	_next_failure = [code, message]


func _take_id() -> int:
	_next_id += 1
	return _next_id


## Fails request `id` when fail_next() was called; returns true then.
func _fail_if_requested(id: int) -> bool:
	if _next_failure.is_empty():
		return false
	_finish_error(id, _next_failure[0], _next_failure[1])
	_next_failure = []
	return true


func _finish(id: int, value: Variant = null) -> void:
	request_completed.emit.call_deferred(id, true, value, 0, "")


func _finish_error(id: int, code: int, message: String) -> void:
	request_completed.emit.call_deferred(id, false, null, code, message)
