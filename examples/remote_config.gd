extends Node
## Attach to a menu/controller with the Firebase autoload installed.
## Call activate_at_safe_point() between puzzle rounds, when the game chooses.

signal settings_ready(values: Dictionary)
signal settings_available(updated_keys: PackedStringArray)

var _config: FirebaseRemoteConfig


func _ready() -> void:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or firebase.remote_config == null:
		push_error("Remote Config module is required for this example")
		return
	_config = firebase.remote_config
	var initialized := await _config.ensure_initialized().wait()
	if not initialized.ok:
		push_error(initialized.error_message)
		return
	var defaults := await _config.set_defaults({"hints_enabled": true, "puzzle_variant": "classic"}).wait()
	if not defaults.ok:
		push_error(defaults.error_message)
		return
	_config.config_updated.connect(_on_config_updated)
	_config.config_update_failed.connect(_on_config_update_failed)
	await _read_settings()
	var fetched := await _config.fetch().wait()
	if fetched.ok:
		# A cached fetch can also succeed. Activation remains a separate decision.
		settings_available.emit(PackedStringArray())
	else:
		push_warning(fetched.error_message)
	var listening := await _config.start_listening().wait()
	if not listening.ok:
		push_warning(listening.error_message)


func activate_at_safe_point() -> void:
	if _config == null:
		return
	var activated := await _config.activate().wait()
	if activated.ok:
		await _read_settings()
	else:
		push_warning(activated.error_message)


func _read_settings() -> void:
	var hints := await _config.get_value("hints_enabled", TYPE_BOOL).wait()
	var variant := await _config.get_value("puzzle_variant").wait()
	if hints.ok and variant.ok and hints.value.conversion_successful and variant.value.conversion_successful:
		settings_ready.emit({"hints_enabled": hints.value.value, "puzzle_variant": variant.value.value})


func _on_config_updated(keys: PackedStringArray) -> void:
	# The SDK has fetched this update; current-round values remain unchanged.
	settings_available.emit(keys)


func _on_config_update_failed(_code: int, message: String) -> void:
	push_warning(message)


func _exit_tree() -> void:
	if _config:
		_config.stop_listening()
