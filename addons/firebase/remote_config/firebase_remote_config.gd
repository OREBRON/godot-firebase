class_name FirebaseRemoteConfig
extends RefCounted
## Remote Config values are active only after activate() or fetch_and_activate().
## Fetch success can reuse the SDK cache; it does not guarantee a network request.
## Mock state is memory-only. Native persistence and conversions belong to the SDK.

signal config_updated(updated_keys: PackedStringArray)
signal config_update_failed(error_code: int, message: String)

# Pinned Firebase C++ ValueSource values (REMOTE precedes DEFAULT).
const STATIC := 0
const REMOTE := 1
const DEFAULT := 2
const LAST_FETCH_SUCCESS := 0
const LAST_FETCH_FAILURE := 1
const LAST_FETCH_PENDING := 2
const FETCH_FAILURE_INVALID := 0
const FETCH_FAILURE_THROTTLED := 1
const FETCH_FAILURE_ERROR := 2
const UPDATE_STREAM_ERROR := 1
const UPDATE_MESSAGE_INVALID := 2
const UPDATE_NOT_FETCHED := 3
const UPDATE_UNAVAILABLE := 4
const MAX_FETCH_TIMEOUT_MS := 2147483647
const VALUE_TYPES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY]

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.config_updated.connect(_on_config_updated)
		_requests.backend.config_update_failed.connect(_on_config_update_failed)


## Result is the same information dictionary as get_info().
func ensure_initialized() -> FirebaseTask:
	return _requests.send(&"ensure_initialized")


## Replaces all defaults. Values are bool, int, finite float, String or bytes.
func set_defaults(values: Dictionary) -> FirebaseTask:
	var reason := validate_defaults(values)
	if not reason.is_empty():
		return _requests.invalid(reason)
	return _requests.send(&"set_defaults", [values])


## Durations are nonnegative milliseconds. The pinned Android SDK rounds down
## to whole seconds internally; use multiples of 1000 for portable settings.
## Timeout is at most MAX_FETCH_TIMEOUT_MS to fit Android HTTP milliseconds.
func set_settings(minimum_fetch_interval_ms: int, fetch_timeout_ms: int) -> FirebaseTask:
	if minimum_fetch_interval_ms < 0 or fetch_timeout_ms < 0 or fetch_timeout_ms > MAX_FETCH_TIMEOUT_MS:
		return _requests.invalid("Remote Config interval must be nonnegative and timeout must be 0..2147483647 milliseconds")
	return _requests.send(&"set_settings", [minimum_fetch_interval_ms, fetch_timeout_ms])


func fetch() -> FirebaseTask:
	return _requests.send(&"fetch")


## Result is true only when fetched values were newly activated.
func activate() -> FirebaseTask:
	return _requests.send(&"activate")


func fetch_and_activate() -> FirebaseTask:
	return _requests.send(&"fetch_and_activate")


## Result: {value, source: STATIC|DEFAULT|REMOTE, conversion_successful}.
## The native conversion flag is reported directly from the platform SDK.
func get_value(key: String, value_type: int = TYPE_STRING) -> FirebaseTask:
	if key.is_empty() or key.to_utf8_buffer().has(0):
		return _requests.invalid("Remote Config key must be non-empty and contain no NUL")
	if not value_type in VALUE_TYPES:
		return _requests.invalid("Remote Config value type must be bool, int, float, String or PackedByteArray")
	return _requests.send(&"get_value", [key, value_type])


## Result: sorted PackedStringArray of the active and default keys that start
## with `prefix`; "" lists every key. Read each one with get_value().
func get_keys(prefix: String = "") -> FirebaseTask:
	if prefix.to_utf8_buffer().has(0):
		return _requests.invalid("Remote Config key prefix must contain no NUL")
	return _requests.send(&"get_keys", [prefix])


## Result: {last_fetch_time_ms, last_fetch_status, last_fetch_failure_reason,
## throttled_end_time_ms}. Time fields are epoch milliseconds; zero means unset.
func get_info() -> FirebaseTask:
	return _requests.send(&"get_info")


## Starts a single realtime listener. Events report fetched keys; they do not activate.
func start_listening() -> FirebaseTask:
	return _requests.send(&"start_listening")


func stop_listening() -> void:
	if _requests.backend:
		_requests.backend.stop_listening()


static func validate_defaults(values: Dictionary) -> String:
	for key in values:
		if not (key is String or key is StringName) or String(key).is_empty() or String(key).to_utf8_buffer().has(0):
			return "Remote Config default keys must be non-empty strings without NUL"
		var value: Variant = values[key]
		if not typeof(value) in VALUE_TYPES:
			return "Remote Config defaults must be bool, int, float, String or PackedByteArray"
		if value is float and not is_finite(value):
			return "Remote Config float defaults must be finite"
	return ""


func _on_config_updated(updated_keys: PackedStringArray) -> void:
	config_updated.emit(updated_keys)


func _on_config_update_failed(error_code: int, message: String) -> void:
	config_update_failed.emit(error_code, message)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_requests) and is_instance_valid(_requests.backend):
		_requests.backend.stop_listening()
