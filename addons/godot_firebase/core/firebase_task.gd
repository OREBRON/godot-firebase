class_name FirebaseTask
extends RefCounted
## Pending Firebase request. Use `var result := await task.wait()`.

signal completed(result: FirebaseResult)

var result: FirebaseResult
var is_done := false


## Returns the result, also when the task finished before the call.
func wait() -> FirebaseResult:
	if not is_done:
		await completed
	return result


func finish(outcome: FirebaseResult) -> void:
	if is_done:
		return
	is_done = true
	result = outcome
	completed.emit(outcome)
