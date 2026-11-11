class_name FirebaseAnalytics
extends RefCounted
## Analytics tasks acknowledge a local SDK call, not upload or durable storage.
## Collection and consent overrides persist in the native SDK. Configure initial
## collection/consent in export settings before the first app startup.

const GRANTED := 0
const DENIED := 1
const CONSENT_KEYS := ["analytics_storage", "ad_storage", "ad_user_data", "ad_personalization"]
const RESERVED_EVENTS := ["ad_activeview", "ad_click", "ad_exposure", "ad_query", "ad_reward", "adunit_exposure", "app_clear_data", "app_exception", "app_remove", "app_store_refund", "app_store_subscription_cancel", "app_store_subscription_convert", "app_store_subscription_renew", "app_update", "app_upgrade", "dynamic_link_app_open", "dynamic_link_app_update", "dynamic_link_first_open", "error", "firebase_campaign", "first_open", "first_visit", "notification_dismiss", "notification_foreground", "notification_open", "notification_receive", "os_update", "session_start", "session_start_with_rollout", "user_engagement"]
const RESERVED_PROPERTIES := ["first_open_time", "last_deep_link_referrer", "user_id"]

var _requests: FirebaseRequests

func _init(requests: FirebaseRequests) -> void:
	_requests = requests

func log_event(name: String, parameters: Dictionary = {}) -> FirebaseTask:
	return _send(&"log_event", [name, parameters], validate_event(name, parameters))

func set_user_id(user_id: String) -> FirebaseTask:
	return _send(&"set_user_id", [user_id], "user_id must contain 1..256 characters" if user_id.is_empty() or user_id.length() > 256 or _has_null(user_id) else "")

func clear_user_id() -> FirebaseTask:
	return _requests.send(&"clear_user_id", [])

func set_user_property(name: String, value: String) -> FirebaseTask:
	var reason := validate_property_name(name)
	if reason.is_empty() and (value.length() > 36 or _has_null(value)):
		reason = "user property value must contain at most 36 characters without NUL"
	return _send(&"set_user_property", [name, value], reason)

func clear_user_property(name: String) -> FirebaseTask:
	return _send(&"clear_user_property", [name], validate_property_name(name))

func set_collection_enabled(enabled: bool) -> FirebaseTask:
	return _requests.send(&"set_collection_enabled", [enabled])

func set_consent(consents: Dictionary) -> FirebaseTask:
	return _send(&"set_consent", [consents], validate_consent(consents))

func reset_analytics_data() -> FirebaseTask:
	return _requests.send(&"reset_analytics_data", [])

func _send(method: StringName, args: Array, reason: String) -> FirebaseTask:
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _requests.send(method, args)

static func _has_null(value: String) -> bool:
	for i in value.length():
		if value.unicode_at(i) == 0:
			return true
	return false

static func validate_name(name: String, max_length: int) -> String:
	if name.is_empty() or name.length() > max_length:
		return "name must contain 1..%d characters" % max_length
	for i in name.length():
		var c := name.unicode_at(i)
		var letter := (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		if not letter and (i == 0 or not ((c >= 48 and c <= 57) or c == 95)):
			return "name must start with an ASCII letter and contain letters, digits or underscores"
	for prefix in ["firebase_", "google_", "ga_"]:
		if name.begins_with(prefix):
			return "reserved name prefix"
	return ""

static func validate_property_name(name: String) -> String:
	return "reserved user property" if name in RESERVED_PROPERTIES else validate_name(name, 24)

static func validate_event(name: String, parameters: Dictionary) -> String:
	var reason := validate_name(name, 40)
	if not reason.is_empty():
		return reason
	if name in RESERVED_EVENTS:
		return "reserved event name"
	if parameters.size() > 25:
		return "events accept at most 25 parameters"
	return _validate_parameters(parameters, true)

## Values are String, int, bool (logged as 1 or 0) or finite float. An event
## parameter may also be an Array of item Dictionaries, such as "items".
static func _validate_parameters(parameters: Dictionary, allow_items: bool) -> String:
	for key in parameters:
		if not key is String:
			return "parameter keys must be strings"
		var reason := validate_name(key, 40)
		if not reason.is_empty():
			return reason
		var value: Variant = parameters[key]
		match typeof(value):
			TYPE_STRING:
				if value.length() > 100 or _has_null(value):
					return "parameter strings accept at most 100 characters without NUL"
			TYPE_INT, TYPE_BOOL:
				pass
			TYPE_FLOAT:
				if not is_finite(value):
					return "parameter numbers must be finite"
			TYPE_ARRAY:
				if not allow_items:
					return "item values must be String, int, bool or finite float"
				for item in value:
					if not item is Dictionary:
						return "parameter arrays must contain only item Dictionaries"
					reason = _validate_parameters(item, false)
					if not reason.is_empty():
						return reason
			_:
				return "parameter values must be String, int, bool, finite float or an Array of item Dictionaries"
	return ""

static func validate_consent(consents: Dictionary) -> String:
	for key in consents:
		if not key is String or key not in CONSENT_KEYS:
			return "unknown consent key"
		if not consents[key] is int or consents[key] not in [GRANTED, DENIED]:
			return "consent must be GRANTED or DENIED"
	return ""
