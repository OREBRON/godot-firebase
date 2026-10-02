extends Node
## Attach to a game scene with the Firebase autoload configured.

func _ready() -> void:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or firebase.crashlytics == null:
		push_error("Configure Firebase and enable Crashlytics in this game first")
		return
	var crashlytics: FirebaseCrashlytics = firebase.crashlytics
	await crashlytics.set_custom_key("smoke_case", "explicit_nonfatal").wait()
	var stack: Array[Dictionary] = [{"function": "_ready", "file": "res://examples/crashlytics_smoke/nonfatal.gd", "line": 13}]
	var result := await crashlytics.record_error("GodotSmokeError", "Explicit GDScript nonfatal smoke", stack).wait()
	print("Nonfatal local call succeeded: ", result.ok)
	var previous := await crashlytics.did_crash_previous_execution().wait()
	print("Previous execution crashed: ", previous.value if previous.ok else previous.error_message)

## Connect explicitly to a debug-only test button. Never called from _ready().
func trigger_native_crash() -> void:
	if not OS.is_debug_build() or not ClassDB.class_exists(&"CrashlyticsSmokeNative"):
		push_error("Build the separate debug-only Crashlytics smoke extension first")
		return
	var fixture: Object = ClassDB.instantiate(&"CrashlyticsSmokeNative")
	fixture.call(&"trigger", "CRASHLYTICS_SMOKE")
