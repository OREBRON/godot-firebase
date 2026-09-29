class_name FirebaseTest
extends SceneTree
## Base for headless tests. Always exits: a missing signal hits the watchdog
## instead of hanging the runner, and a runtime script error, which silently
## ends the running coroutine, counts as a failure.

const WATCHDOG_SECONDS := 10.0
const FirebaseNode := preload("res://addons/firebase/core/firebase.gd")

var failures: Array[String] = []
var _script_errors := ScriptErrorLogger.new()


class ScriptErrorLogger extends Logger:
	var messages: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			_mutex.lock()
			messages.append("%s:%d %s" % [file, line, code])
			_mutex.unlock()


func _initialize() -> void:
	OS.add_logger(_script_errors)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_start.call_deferred()


## Override with the test body. May await.
func _run() -> void:
	pass


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


## Returns a Firebase node wired to `backends`; default: fresh mocks for every module.
func mock_firebase(backends: Dictionary = {
	"auth": FirebaseAuthMock.new(), "firestore": FirebaseFirestoreMock.new(), "storage": FirebaseStorageMock.new(),
	"database": FirebaseDatabaseMock.new(), "functions": FirebaseFunctionsMock.new(),
}) -> Node:
	var firebase: Node = FirebaseNode.new()
	firebase.setup(backends)
	root.add_child(firebase)
	return firebase


func _start() -> void:
	await _run()
	failures.append_array(_script_errors.messages)
	print("%s: %s" % [get_script().resource_path.get_file(), "ok" if failures.is_empty() else "%d failed" % failures.size()])
	quit(0 if failures.is_empty() else 1)


func _on_watchdog() -> void:
	push_error("watchdog: test did not finish in %d s" % WATCHDOG_SECONDS)
	quit(2)
