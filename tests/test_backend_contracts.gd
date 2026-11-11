extends FirebaseTest
## Reflection checks run against installed native classes; editor stubs are explicitly skipped.

const TEST_HELPERS := {
	"common": ["fail_next"],
	"auth": ["delay_next_sign_in", "complete_pending_sign_in", "set_provider_account", "shutdown_for_test"],
	"firestore": ["set_auto_acknowledge", "acknowledge_pending_writes", "simulate_user_change"],
	"database": ["simulate_connection"],
	"storage": [],
	"functions": [],
	"analytics": [],
	"remote_config": ["set_server_values", "set_network_available", "advance_time", "throttle_until", "publish_update", "publish_error"],
	"crashlytics": [],
}

func _run() -> void:
	check(FirebaseNode.native_class_name("remote_config") == &"FirebaseRemoteConfigNative", "underscore module maps to native PascalCase")
	check(FirebaseNode.native_class_name("auth") == &"FirebaseAuthNative", "existing class mapping retained")
	var database_mock_path := "res://addons/firebase/database/firebase_database_mock.gd"
	if ResourceLoader.exists(database_mock_path):
		var methods := _script_entries(load(database_mock_path), false)
		check(methods.initialize.args.size() == 2, "derived initialize overrides inherited reflection entry")
		check(methods.initialize.default_args == [false, ""], "derived initialize keeps persistence and emulator defaults")
	for module in FirebaseNode.MODULES:
		var path := "res://addons/firebase/%s/firebase_%s_mock.gd" % [module, module]
		if not ResourceLoader.exists(path):
			print("contract %s: skipped (module not installed)" % module)
			continue
		var native_name := FirebaseNode.native_class_name(module)
		if not ClassDB.class_exists(native_name):
			print("contract %s: skipped (native class unavailable; no native parity result)" % module)
			continue
		var script: Script = load(path)
		var mock_methods := _script_entries(script, false)
		for helper in TEST_HELPERS.common + TEST_HELPERS.get(module, []):
			mock_methods.erase(helper)
		var native_methods := _entries(ClassDB.class_get_method_list(native_name, true))
		_compare(module + " method", mock_methods, native_methods)
		var native_signals := _entries(ClassDB.class_get_signal_list(native_name))
		for inherited in ClassDB.class_get_signal_list(&"RefCounted"):
			native_signals.erase(inherited.name)
		_compare(module + " signal", _script_entries(script, true), native_signals)


func _script_entries(script: Script, signals: bool) -> Dictionary:
	var entries: Dictionary = {}
	while script != null:
		var own := _entries(script.get_script_signal_list() if signals else script.get_script_method_list())
		for key in own:
			if not entries.has(key):
				entries[key] = own[key]
		script = script.get_base_script()
	return entries


func _entries(methods: Array) -> Dictionary:
	var entries := {}
	for method in methods:
		var name: String = method.name
		# Godot includes inherited script methods after the derived declaration.
		if not entries.has(name) and not name.begins_with("_") and not name.begins_with("@"):
			entries[name] = method
	return entries


func _compare(label: String, mock_entries: Dictionary, native_entries: Dictionary) -> void:
	check(mock_entries.size() == native_entries.size(), "%s count: mock %s native %s" % [label, mock_entries.keys(), native_entries.keys()])
	for name in mock_entries:
		check(native_entries.has(name), "%s %s exists in native" % [label, name])
		if not native_entries.has(name):
			continue
		var a: Dictionary = mock_entries[name]
		var b: Dictionary = native_entries[name]
		check(a.args.size() == b.args.size(), "%s %s argument count" % [label, name])
		for i in mini(a.args.size(), b.args.size()):
			check(a.args[i].type == b.args[i].type, "%s %s argument %d type" % [label, name, i])
		check(a.get("default_args", []) == b.get("default_args", []), "%s %s default arguments" % [label, name])
		if a.has("return") and b.has("return"):
			check(a.return.type == b.return.type, "%s %s return type" % [label, name])
