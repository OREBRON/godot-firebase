class_name FirebaseAnalyticsMock
extends FirebaseMockModule
## In-memory observations of local SDK calls, not a server event queue.

var events: Array[Dictionary] = []
var user_id := ""
var user_properties := {}
var collection_enabled := true
var consents := {"analytics_storage": 0, "ad_storage": 0, "ad_user_data": 0, "ad_personalization": 0}

func log_event(name: String, parameters: Dictionary = {}) -> int:
	return _apply(func():
		if collection_enabled:
			events.append({"name": name, "parameters": parameters.duplicate(true)}))

func set_user_id(value: String) -> int:
	return _apply(func(): user_id = value)

func clear_user_id() -> int:
	return _apply(func(): user_id = "")

func set_user_property(name: String, value: String) -> int:
	return _apply(func(): user_properties[name] = value)

func clear_user_property(name: String) -> int:
	return _apply(func(): user_properties.erase(name))

func set_collection_enabled(enabled: bool) -> int:
	return _apply(func(): collection_enabled = enabled)

func set_consent(values: Dictionary) -> int:
	return _apply(func(): consents.merge(values, true))

func reset_analytics_data() -> int:
	return _apply(func():
		events.clear()
		user_id = ""
		user_properties.clear())
