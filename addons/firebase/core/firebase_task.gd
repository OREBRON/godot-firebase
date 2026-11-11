class_name FirebaseTask
extends RefCounted
## Pending Firebase request. Use `var result := await task.wait()`.

signal completed(result: FirebaseResult)

var result: FirebaseResult
var is_done := false


## Returns the result, also when the task finished before the call.
## With `timeout_seconds` > 0 it returns an ERR_TIMEOUT failure if no result
## arrived by then. Only this wait ends: the request is not cancelled, and the
## task still finishes with the real result, which a later wait() returns.
func wait(timeout_seconds := 0.0) -> FirebaseResult:
	if is_done:
		return result
	if timeout_seconds <= 0.0:
		return await completed
	# Whichever comes first finishes `first`; this task keeps its own result.
	var first := FirebaseTask.new()
	completed.connect(first.finish)
	# Real seconds: pausing the game or changing time_scale does not stretch a network wait.
	var timer := (Engine.get_main_loop() as SceneTree).create_timer(timeout_seconds, true, false, true)
	timer.timeout.connect(first.finish.bind(FirebaseResult.failure(FirebaseResult.ERR_TIMEOUT,
			"no result after %s seconds; the request keeps running" % timeout_seconds)))
	return await first.completed


func finish(outcome: FirebaseResult) -> void:
	if is_done:
		return
	is_done = true
	result = outcome
	completed.emit(outcome)
