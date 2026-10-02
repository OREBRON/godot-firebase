extends FirebaseTest


func _run() -> void:
	check(FileAccess.file_exists("res://addons/firebase/remote_config/firebase_remote_config.gd"), "Remote Config module exists")
	if not FileAccess.file_exists("res://addons/firebase/remote_config/firebase_remote_config.gd"):
		return
	var backend: RefCounted = load("res://addons/firebase/remote_config/firebase_remote_config_mock.gd").new()
	var api: RefCounted = load("res://addons/firebase/remote_config/firebase_remote_config.gd").new(FirebaseRequests.new(backend))
	var result: FirebaseResult = await api.ensure_initialized().wait()
	check(result.ok and result.value.last_fetch_time_ms == 0, "initialization returns cold-start info")
	result = await api.get_value("missing", TYPE_INT).wait()
	check(result.ok and result.value.value == 0 and result.value.source == api.STATIC, "missing key returns static typed value")
	result = await api.set_defaults({"level": 1, "enabled": true, "label": "hello", "bytes": PackedByteArray([1, 2]), "bad_int": "oops"}).wait()
	check(result.ok, "scalar and byte defaults accepted")
	result = await api.get_value("level", TYPE_INT).wait()
	check(result.value == {"value": 1, "source": api.DEFAULT, "conversion_successful": true}, "default value source and conversion")
	result = await api.get_value("bytes", TYPE_PACKED_BYTE_ARRAY).wait()
	check(result.value.value == PackedByteArray([1, 2]), "bytes roundtrip without string conversion")
	result = await api.get_value("bad_int", TYPE_INT).wait()
	check(result.ok and result.value.value == 0 and not result.value.conversion_successful, "invalid scalar conversion reports failure")
	for bad in [{"a": []}, {"a": {}}, {"a": null}, {"a": INF}, {"": 1}, {3: 1}]:
		result = await api.set_defaults(bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid defaults rejected")
	result = await api.get_value("level", TYPE_DICTIONARY).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "aggregate read type rejected")
	for bad in [[-1, 1000], [1000, -1], [0, 2147483648]]:
		result = await api.set_settings(bad[0], bad[1]).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "unsafe millisecond settings rejected")
	result = await api.set_settings(9223372036854775807, 2147483647).wait()
	check(result.ok, "large interval and int32 timeout boundaries accepted")
	await api.set_settings(0, 30000).wait()
	backend.call("set_server_values", {"level": 2, "label": "remote"})
	result = await api.fetch().wait()
	check(result.ok, "fetch succeeds")
	result = await api.get_value("level", TYPE_INT).wait()
	check(result.value.value == 1 and result.value.source == api.DEFAULT, "fetch does not activate")
	result = await api.activate().wait()
	check(result.ok and result.value == true, "activate reports changed once")
	result = await api.activate().wait()
	check(result.ok and result.value == false, "second activate reports no change")
	result = await api.get_value("level", TYPE_INT).wait()
	check(result.value.value == 2 and result.value.source == api.REMOTE, "activated remote value is visible")
	backend.call("set_network_available", false)
	result = await api.fetch().wait()
	check(not result.ok, "offline fetch fails")
	result = await api.get_value("level", TYPE_INT).wait()
	check(result.value.value == 2, "offline read preserves activated state")
	backend.call("set_network_available", true)
	backend.call("throttle_until", 10000)
	result = await api.fetch().wait()
	check(not result.ok, "throttled fetch fails")
	result = await api.get_info().wait()
	check(result.value.last_fetch_failure_reason == api.FETCH_FAILURE_THROTTLED and result.value.throttled_end_time_ms == 10000, "throttle info retains milliseconds")
	backend.call("advance_time", 10000)
	backend.call("set_server_values", {"level": 3})
	result = await api.fetch_and_activate().wait()
	check(result.ok and result.value, "fetch and activate applies new values")
	await api.set_settings(10000, 30000).wait()
	backend.call("set_server_values", {"level": 4})
	result = await api.fetch_and_activate().wait()
	check(result.ok and not result.value, "fetch within minimum interval reuses cached fetch")
	check((await api.get_value("level", TYPE_INT).wait()).value.value == 3, "cached fetch keeps active values")
	await _listeners(api, backend)
	result = await api.set_defaults({"replacement": "yes"}).wait()
	check(result.ok and (await api.get_value("bad_int").wait()).value.source == api.STATIC, "set_defaults replaces previous defaults")
	var teardown_events: Array = []
	backend.config_updated.connect(func(keys): teardown_events.append(keys))
	await api.start_listening().wait()
	backend.call("publish_update", {"level": 10})
	var api_ref: WeakRef = weakref(api)
	api = null
	await process_frame
	check(api_ref.get_ref() == null and teardown_events.is_empty(), "API teardown stops listener and suppresses queued delivery")


func _listeners(api: RefCounted, backend: RefCounted) -> void:
	var updates: Array = []
	var errors: Array = []
	api.config_updated.connect(func(keys): updates.append(keys))
	api.config_update_failed.connect(func(code, message): errors.append([code, message]))
	await api.start_listening().wait()
	await api.start_listening().wait()
	backend.call("publish_update", {"level": 5})
	await process_frame
	check(updates.size() == 1 and updates[0] == PackedStringArray(["level"]), "duplicate start retains one listener")
	check((await api.get_value("level", TYPE_INT).wait()).value.value == 3, "real-time update does not activate")
	check((await api.activate().wait()).value, "explicit activate applies realtime fetched values")
	backend.call("publish_error", 4, "unavailable")
	await process_frame
	check(errors == [[4, "unavailable"]], "listener errors preserve code and message")
	backend.call("publish_update", {"level": 6})
	api.stop_listening()
	await process_frame
	check(updates.size() == 1, "stop suppresses queued callbacks")
	await api.start_listening().wait()
	backend.call("publish_update", {"level": 7})
	api.stop_listening()
	await api.start_listening().wait()
	await process_frame
	check(updates.size() == 1, "restart does not revive previous listener generation")
	backend.call("publish_update", {"level": 8})
	await process_frame
	check(updates.size() == 2, "new listener receives updates after restart")
	backend.call("set_network_available", false)
	backend.call("publish_update", {"level": 9})
	await process_frame
	check(updates.size() == 2, "offline listener receives no server publish")
	backend.call("set_network_available", true)
	await process_frame
	check(updates.size() == 3, "reconnected listener receives latest published update")
	api.stop_listening()
