extends FirebaseTest

func _run() -> void:
	var path := "res://addons/firebase/analytics/firebase_analytics_mock.gd"
	check(ResourceLoader.exists(path), "Analytics backend installed")
	if not ResourceLoader.exists(path):
		return
	var backend: Object = load(path).new()
	var firebase := mock_firebase({"analytics": backend})
	var api: Object = firebase.analytics
	var result: FirebaseResult = await api.log_event("level_end", {"level": 7, "time": 2.5, "mode": "puzzle"}).wait()
	check(result.ok and backend.events.size() == 1, "valid scalar event recorded")
	for name in ["", "1bad", "firebase_custom", "ga_custom", "google_custom", "session_start", "a".repeat(41)]:
		result = await api.log_event(name).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid/reserved event rejected: " + name)
	for values in [{"nested": {}}, {"value": true}, {"value": INF}, {"value": "a".repeat(101)}, {"firebase_key": 1}, {1: "x"}]:
		result = await api.log_event("level_end", values).wait()
		check(not result.ok, "invalid event parameter rejected")
	var many := {}
	for i in 26:
		many["p%d" % i] = i
	result = await api.log_event("level_end", many).wait()
	check(not result.ok, "26 parameters rejected")
	result = await api.set_collection_enabled(false).wait()
	check(result.ok, "collection switch is a local success")
	result = await api.log_event("level_end").wait()
	check(result.ok and backend.events.size() == 1, "collection disabled drops event with local success")
	result = await api.set_consent({"analytics_storage": 1, "ad_storage": 1}).wait()
	check(result.ok, "consent accepted")
	result = await api.set_consent({"ad_storage": 0}).wait()
	check(result.ok and backend.consents.analytics_storage == 1 and backend.consents.ad_storage == 0, "consent partial update preserves omitted keys")
	result = await api.set_consent({"unknown": 0}).wait()
	check(not result.ok, "unknown consent rejected")
	result = await api.set_consent({"ad_storage": true}).wait()
	check(not result.ok, "consent bool is not enum")
	result = await api.set_user_id("player-1").wait()
	check(result.ok and backend.user_id == "player-1", "explicit user id set")
	result = await api.clear_user_id().wait()
	check(result.ok and backend.user_id.is_empty(), "user id cleared")
	result = await api.set_user_property("play_style", "casual").wait()
	check(result.ok and backend.user_properties.play_style == "casual", "property set")
	result = await api.clear_user_property("play_style").wait()
	check(result.ok and not backend.user_properties.has("play_style"), "property cleared")
	result = await api.set_user_property("a".repeat(25), "x").wait()
	check(not result.ok, "property name max24")
	result = await api.set_user_property("mode", "a".repeat(37)).wait()
	check(not result.ok, "property value max36")
	result = await api.reset_analytics_data().wait()
	check(result.ok and backend.events.is_empty(), "analytics local data reset")
