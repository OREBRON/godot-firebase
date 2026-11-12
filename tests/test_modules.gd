extends FirebaseTest
## The autoload starts every module whose folder exists, with mocks on desktop
## when no native build is configured.


## A package installed without the analytics folder.
class WithoutAnalytics extends "res://addons/firebase/core/firebase.gd":
	func _api_path(module: String) -> String:
		return "res://addons/firebase/analytics/missing.gd" if module == "analytics" else super(module)


class ErrorLog extends Logger:
	var messages: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR and code.begins_with("Firebase: "):
			_mutex.lock()
			messages.append(code)
			_mutex.unlock()


func _run() -> void:
	_backend_for_missing_module()
	var firebase: Node = FirebaseNode.new()
	root.add_child(firebase)
	check(firebase.auth is FirebaseAuth and firebase.firestore is FirebaseFirestore, "auth and firestore APIs start")
	check(firebase.storage is FirebaseStorage and firebase.database is FirebaseDatabase and firebase.functions is FirebaseFunctions, "storage, database and functions APIs start")
	for module in firebase.MODULES:
		if not ResourceLoader.exists("res://addons/firebase/%s/firebase_%s.gd" % [module, module]):
			check(firebase.get(module) == null and not firebase.is_available(module), "%s is absent when not installed" % module)
			continue
		check(firebase.is_available(module), "%s has a backend" % module)
		if not ClassDB.class_exists(&"FirebaseAppNative"):
			check(firebase.is_mock(module), "%s uses the mock without native" % module)
	check(not firebase.is_available("unknown_product"), "unknown module is unavailable")

	var result: FirebaseResult = await firebase.auth.sign_in_anonymously().wait()
	check(result.ok, "auth works through the autoload")


func _backend_for_missing_module() -> void:
	var errors := ErrorLog.new()
	OS.add_logger(errors)
	var firebase := WithoutAnalytics.new()
	firebase.setup({"auth": FirebaseAuthMock.new(), "analytics": FirebaseAnalyticsMock.new()})
	OS.remove_logger(errors)
	check(firebase.auth is FirebaseAuth, "installed module starts next to a missing one")
	check(firebase.analytics == null and not firebase.is_available("analytics"), "backend for a missing module leaves it unavailable")
	check(errors.messages.size() == 1 and "analytics" in errors.messages[0], "backend for a missing module reports its name")
	firebase.free()
