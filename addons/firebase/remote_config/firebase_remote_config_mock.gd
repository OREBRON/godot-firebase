class_name FirebaseRemoteConfigMock
extends FirebaseMockModule
## Memory-only Remote Config. Fetch times and the minimum fetch interval use the
## system clock like the SDKs. Helpers control server/time/network; this does
## not emulate native disk persistence or platform conversion quirks.

signal config_updated(updated_keys: PackedStringArray)
signal config_update_failed(error_code: int, message: String)

var _defaults: Dictionary = {}
var _fetched: Dictionary = {}
var _active: Dictionary = {}
var _server: Dictionary = {}
var _fetched_version := 0
var _active_version := 0
var _minimum_fetch_interval_ms := 43200000
var _fetch_timeout_ms := 30000
var _frozen_clock_ms := -1
var _clock_offset_ms := 0
var _network_available := true
var _listening := false
var _listener_generation := 0
var _reconnect_pending := false
var _info := {"last_fetch_time_ms": 0, "last_fetch_status": FirebaseRemoteConfig.LAST_FETCH_PENDING,
	"last_fetch_failure_reason": FirebaseRemoteConfig.FETCH_FAILURE_INVALID, "throttled_end_time_ms": 0}


## Tests pass `frozen_clock_ms` to pin the clock to that epoch millisecond;
## only advance_time() moves it then.
func _init(frozen_clock_ms := -1) -> void:
	_frozen_clock_ms = frozen_clock_ms


func ensure_initialized() -> int:
	return get_info()


func set_defaults(values: Dictionary) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	var reason := FirebaseRemoteConfig.validate_defaults(values)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	else:
		_defaults = values.duplicate(true)
		_finish(id)
	return id


func set_settings(minimum_fetch_interval_ms: int, fetch_timeout_ms: int) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if minimum_fetch_interval_ms < 0 or fetch_timeout_ms < 0 or fetch_timeout_ms > FirebaseRemoteConfig.MAX_FETCH_TIMEOUT_MS:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "Remote Config interval must be nonnegative and timeout must be 0..2147483647 milliseconds")
	else:
		_minimum_fetch_interval_ms = minimum_fetch_interval_ms
		_fetch_timeout_ms = fetch_timeout_ms
		_finish(id)
	return id


func fetch() -> int:
	var id := _take_id()
	if _fetch(id):
		_finish(id)
	return id


func activate() -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, _activate())
	return id


func fetch_and_activate() -> int:
	var id := _take_id()
	if _fetch(id):
		_finish(id, _activate())
	return id


func get_value(key: String, value_type: int = TYPE_STRING) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if key.is_empty() or key.to_utf8_buffer().has(0) or not value_type in FirebaseRemoteConfig.VALUE_TYPES:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "invalid Remote Config key or value type")
		return id
	var source := FirebaseRemoteConfig.REMOTE if _active.has(key) else (FirebaseRemoteConfig.DEFAULT if _defaults.has(key) else FirebaseRemoteConfig.STATIC)
	var value: Variant = _active.get(key, _defaults.get(key, ""))
	var converted := _convert(value, value_type, source == FirebaseRemoteConfig.STATIC)
	_finish(id, {"value": converted.value, "source": source, "conversion_successful": converted.ok})
	return id


func get_info() -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, _info.duplicate())
	return id


func start_listening() -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if not _listening:
		_listener_generation += 1
		_listening = true
	_finish(id)
	return id


func stop_listening() -> void:
	_listening = false
	_listener_generation += 1
	_reconnect_pending = false


## Test control: changes future fetch responses without performing a publish.
func set_server_values(values: Dictionary) -> void:
	_server = values.duplicate(true)


## Test control: simulates connectivity, including an update published offline.
func set_network_available(available: bool) -> void:
	_network_available = available
	if available and _reconnect_pending and _listening:
		_reconnect_pending = false
		_publish_server_update()


## Test control: moves the mock clock forward without waiting.
func advance_time(milliseconds: int) -> void:
	if milliseconds >= 0:
		_clock_offset_ms += milliseconds


## Test control: specifies the server's throttle end time in epoch milliseconds.
func throttle_until(epoch_milliseconds: int) -> void:
	_info.throttled_end_time_ms = maxi(epoch_milliseconds, 0)


## Test control: publishes a complete server template, fetched but not activated.
func publish_update(values: Dictionary) -> void:
	_server = values.duplicate(true)
	if not _listening:
		return
	if not _network_available:
		_reconnect_pending = true
		return
	_publish_server_update()


## Test control: emits an SDK realtime listener error without changing active values.
func publish_error(code: int, message: String) -> void:
	if _listening:
		_deliver_error.call_deferred(_listener_generation, code, message)


func _fetch(id: int) -> bool:
	if _fail_if_requested(id):
		_info.last_fetch_status = FirebaseRemoteConfig.LAST_FETCH_FAILURE
		_info.last_fetch_failure_reason = FirebaseRemoteConfig.FETCH_FAILURE_ERROR
		return false
	if _info.last_fetch_time_ms > 0 and _now_ms() - _info.last_fetch_time_ms < _minimum_fetch_interval_ms:
		_info.last_fetch_status = FirebaseRemoteConfig.LAST_FETCH_SUCCESS
		_info.last_fetch_failure_reason = FirebaseRemoteConfig.FETCH_FAILURE_INVALID
		return true
	if not _network_available or _now_ms() < _info.throttled_end_time_ms:
		_info.last_fetch_status = FirebaseRemoteConfig.LAST_FETCH_FAILURE
		_info.last_fetch_failure_reason = FirebaseRemoteConfig.FETCH_FAILURE_THROTTLED if _network_available else FirebaseRemoteConfig.FETCH_FAILURE_ERROR
		_finish_error(id, 1, "Remote Config fetch throttled" if _network_available else "Remote Config server unavailable")
		return false
	_store_fetch()
	return true


func _store_fetch() -> void:
	if _fetched_version == 0 or _server != _fetched:
		_fetched = _server.duplicate(true)
		_fetched_version += 1
	_info.last_fetch_time_ms = _now_ms()
	_info.last_fetch_status = FirebaseRemoteConfig.LAST_FETCH_SUCCESS
	_info.last_fetch_failure_reason = FirebaseRemoteConfig.FETCH_FAILURE_INVALID
	_info.throttled_end_time_ms = 0


func _activate() -> bool:
	if _active_version == _fetched_version:
		return false
	_active = _fetched.duplicate(true)
	_active_version = _fetched_version
	return true


func _publish_server_update() -> void:
	var keys := PackedStringArray()
	for key in _server:
		if not _active.has(key) or _server[key] != _active[key]:
			keys.append(key)
	for key in _active:
		if not _server.has(key):
			keys.append(key)
	_store_fetch()
	keys.sort()
	if not keys.is_empty():
		_deliver_update.call_deferred(_listener_generation, keys)


func _now_ms() -> int:
	var base := _frozen_clock_ms if _frozen_clock_ms >= 0 else int(Time.get_unix_time_from_system() * 1000)
	return base + _clock_offset_ms


func _deliver_update(generation: int, keys: PackedStringArray) -> void:
	if _listening and generation == _listener_generation:
		config_updated.emit(keys)


func _deliver_error(generation: int, code: int, message: String) -> void:
	if _listening and generation == _listener_generation:
		config_update_failed.emit(code, message)


func _convert(value: Variant, value_type: int, is_static: bool) -> Dictionary:
	var text: String = value.get_string_from_utf8() if value is PackedByteArray else str(value)
	match value_type:
		TYPE_STRING:
			return {"value": text, "ok": true}
		TYPE_PACKED_BYTE_ARRAY:
			return {"value": value.duplicate() if value is PackedByteArray else text.to_utf8_buffer(), "ok": true}
		TYPE_BOOL:
			var normalized := text.to_lower()
			return {"value": normalized in ["1", "true", "t", "yes", "y", "on"], "ok": is_static or normalized in ["1", "true", "t", "yes", "y", "on", "0", "false", "f", "no", "n", "off", ""]}
		TYPE_INT:
			var valid := text.is_valid_int()
			return {"value": text.to_int() if valid else 0, "ok": is_static or valid}
		TYPE_FLOAT:
			var valid := text.is_valid_float() and is_finite(text.to_float())
			return {"value": text.to_float() if valid else 0.0, "ok": is_static or valid}
	return {"value": null, "ok": false}
