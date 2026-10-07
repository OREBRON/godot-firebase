extends FirebaseTest
## Rewarded ads through Firebase.admob on the editor mock: load, show, events,
## single use, expiry, the single full-screen rule and input validation.

const REWARDED := {"rewarded": true, "reward_type": "reward", "reward_amount": 1}
const NOT_REWARDED := {"rewarded": false, "reward_type": "", "reward_amount": 0}
const FULL_SHOW := ["opened", "impression", "reward_earned", "closed"]
# Backend method and complete arguments; FirebaseAdmob rejects each before the backend.
const INVALID_CALLS := [
	["load_rewarded", [""]],
	["load_rewarded", ["ca-app-pub-394025609994254/5224354917"]],
	["load_rewarded", ["ca-app-pub-3940256099942544/522435491"]],
	["load_rewarded", ["ca-app-pub-3940256099942544~5224354917"]],
	["load_rewarded", ["ca-app-pub-3940256099942544/5224354917\n"]],
	["load_rewarded", [" ca-app-pub-3940256099942544/5224354917"]],
	["show_rewarded", [0, {}]],
	["show_rewarded", [-1, {}]],
	["show_rewarded", [1, {"user_id": 7}]],
	["show_rewarded", [1, {"user_id": "u", "other": "x"}]],
	["show_rewarded", [1, {&"user_id": "u"}]],
	["request_consent", [{"debug_geography": "us"}]],
	["request_consent", [{"debug_geography": 1}]],
	["request_consent", [{"test_device_hashed_ids": "HASH"}]],
	["request_consent", [{"test_device_hashed_ids": ["HASH", 1]}]],
	["request_consent", [{"tag_for_under_age": true}]],
	["set_request_configuration", [{"max_ad_content_rating": "R"}]],
	["set_request_configuration", [{"age_restricted_treatment": "adult"}]],
	["set_request_configuration", [{"age_restricted_treatment": true}]],
	["set_request_configuration", [{"test_device_ids": [2]}]],
	["set_request_configuration", [{"child_directed": true}]],
	["set_request_configuration", [{"under_age_of_consent": true}]],
]

var _events: Array[Dictionary] = []


class ReleaseSpy extends FirebaseAdmobMock:
	var released: Array[int] = []

	func release_rewarded(ad_id: int) -> void:
		released.append(ad_id)
		super(ad_id)


func _run() -> void:
	ProjectSettings.set_setting(FirebaseAdmobMock.CONSENT_SETTING, "not_required")
	check(FirebaseNode.native_class_name("admob") == &"FirebaseAdmobNative", "admob maps to FirebaseAdmobNative")
	check(FirebaseAdmob.test_rewarded_ad_unit() == FirebaseAdmob.TEST_REWARDED_ANDROID, "desktop uses the Android test unit")
	for unit in [FirebaseAdmob.TEST_REWARDED_ANDROID, FirebaseAdmob.TEST_REWARDED_IOS]:
		check(FirebaseAdmob.validate_ad_unit_id(unit).is_empty(), "test unit %s is a valid ad unit ID" % unit)
	var backend := ReleaseSpy.new(0)
	var firebase := mock_firebase({"admob": backend})
	var admob: FirebaseAdmob = firebase.admob
	check(admob is FirebaseAdmob and firebase.is_mock("admob"), "Firebase.admob uses the mock without native")
	admob.ad_event.connect(_on_ad_event)
	await _invalid_input_never_reaches_backend(admob, backend)
	await _consent_gate(admob)
	await _show(admob, backend)
	await _single_full_screen(admob)
	await _expiry(admob, backend)
	await _release(admob, backend)
	await _load_failures(admob, backend)
	await _request_configuration(admob, backend)
	await _mock_revalidates(backend)


func _invalid_input_never_reaches_backend(admob: FirebaseAdmob, backend: FirebaseAdmobMock) -> void:
	var completions := [0]
	var count := func(_id: int, _ok: bool, _value: Variant, _code: int, _message: String) -> void: completions[0] += 1
	backend.request_completed.connect(count)
	for call: Array in INVALID_CALLS:
		var result: FirebaseResult = await admob.callv(call[0], call[1]).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "%s%s is rejected" % [call[0], var_to_str(call[1])])
	admob.release_rewarded(0)
	admob.release_rewarded(-3)
	await process_frame
	check(completions[0] == 0 and backend.released.is_empty(), "invalid input never reaches the backend")
	backend.request_completed.disconnect(count)


func _consent_gate(admob: FirebaseAdmob) -> void:
	var result := await admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit()).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_UNAVAILABLE, "load before request_consent is unavailable")
	var consent := admob.request_consent()
	result = await admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit()).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_UNAVAILABLE, "load before request_consent completes is unavailable")
	result = await consent.wait()
	check(result.ok and result.value == {"can_request_ads": true, "consent_status": "not_required", "privacy_options_required": false}, "consent is not required by default")
	for options in [{"debug_geography": "eea", "test_device_hashed_ids": PackedStringArray(["HASH"])}, {"debug_geography": "regulated_us_state", "test_device_hashed_ids": ["HASH"]}, {"debug_geography": "other"}]:
		result = await admob.request_consent(options).wait()
		check(result.ok, "debug consent options %s are accepted" % var_to_str(options))


func _show(admob: FirebaseAdmob, backend: FirebaseAdmobMock) -> void:
	var ad := await _load(admob)
	check(await _load(admob) != ad, "every load returns a new ad id")
	var verification := {"user_id": "player-1", "custom_data": "energy"}
	_events.clear()
	var result := await admob.show_rewarded(ad, verification).wait()
	check(result.ok and result.value == REWARDED, "show completes with the default reward")
	check(_event_names() == FULL_SHOW, "show emits opened, impression, reward_earned and closed before completing")
	check(_events.all(func(event: Dictionary) -> bool: return event.ad_id == ad), "events carry the shown ad id")
	check(_on_separate_frames(), "ad events arrive on separate frames")
	verification.user_id = "changed"
	check(backend.last_verification == {"user_id": "player-1", "custom_data": "energy"}, "the mock keeps the verification of the last show")
	result = await admob.show_rewarded(ad).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "a shown ad cannot be shown again")

	backend.close_next_early()
	ad = await _load(admob)
	_events.clear()
	result = await admob.show_rewarded(ad, {"user_id": "player-1"}).wait()
	check(result.ok and result.value == NOT_REWARDED, "closing early earns no reward")
	check(_event_names() == ["opened", "impression", "closed"], "closing early skips reward_earned")
	check(backend.last_verification == {"user_id": "player-1"}, "verification may omit custom_data")
	backend.set_mock_reward("energy", 5)
	result = await admob.show_rewarded(await _load(admob)).wait()
	check(result.ok and result.value == {"rewarded": true, "reward_type": "energy", "reward_amount": 5}, "closing early applies to one show; the mock reward is configurable")
	check(backend.last_verification.is_empty(), "verification defaults to empty")
	backend.set_mock_reward("reward", 1)


func _single_full_screen(admob: FirebaseAdmob) -> void:
	var first := await _load(admob)
	var second := await _load(admob)
	var showing := admob.show_rewarded(first)
	var busy: Array[FirebaseTask] = [admob.show_rewarded(second), admob.request_consent(), admob.show_privacy_options()]
	var loading := admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit())
	for task in busy:
		var rejected := await task.wait()
		check(not rejected.ok and rejected.error_code == FirebaseResult.ERR_BUSY, "a second full-screen request fails while an ad shows")
	check((await loading.wait()).ok, "loading continues while an ad shows")
	check((await showing.wait()).ok, "the open ad completes")
	var result := await admob.show_rewarded(second).wait()
	check(result.ok and result.value == REWARDED, "a busy rejection keeps the ad")


func _expiry(admob: FirebaseAdmob, backend: FirebaseAdmobMock) -> void:
	var ad := await _load(admob)
	backend.advance_time(FirebaseAdmob.AD_EXPIRY_MS)
	check((await admob.show_rewarded(ad).wait()).ok, "an ad can be shown until exactly one hour after loading")
	ad = await _load(admob)
	backend.advance_time(FirebaseAdmob.AD_EXPIRY_MS + 1)
	_events.clear()
	var result := await admob.show_rewarded(ad).wait()
	check(not result.ok and result.error_code == FirebaseAdmob.ERROR_AD_EXPIRED, "an ad older than one hour fails with ERROR_AD_EXPIRED")
	check(_event_names() == ["failed_to_show"] and _events[0].ad_id == ad, "an expired ad emits failed_to_show")
	result = await admob.show_rewarded(ad).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "an expired ad is released")


func _release(admob: FirebaseAdmob, backend: ReleaseSpy) -> void:
	var ad := await _load(admob)
	admob.release_rewarded(ad)
	admob.release_rewarded(ad)
	check(backend.released == [ad, ad], "release reaches the backend for valid ids")
	var result := await admob.show_rewarded(ad).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "a released ad is unknown")


func _load_failures(admob: FirebaseAdmob, backend: FirebaseAdmobMock) -> void:
	backend.simulate_no_fill()
	var result := await admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit()).wait()
	check(not result.ok and result.error_code == FirebaseAdmob.ERROR_NO_FILL, "simulate_no_fill fails the next load")
	check(await _load(admob) > 0, "no fill applies to one load")
	backend.fail_next(FirebaseAdmob.ERROR_NETWORK, "offline")
	result = await admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit()).wait()
	check(not result.ok and result.error_code == FirebaseAdmob.ERROR_NETWORK and result.error_message == "offline", "platform load errors keep code and message")


func _request_configuration(admob: FirebaseAdmob, backend: FirebaseAdmobMock) -> void:
	var config := {"test_device_ids": PackedStringArray(["DEVICE"]), "max_ad_content_rating": "PG", "age_restricted_treatment": "child"}
	var result := await admob.set_request_configuration(config).wait()
	check(result.ok and backend.request_configuration == config, "request configuration reaches the backend")
	result = await admob.set_request_configuration({"test_device_ids": ["DEVICE"], "age_restricted_treatment": "teen"}).wait()
	check(result.ok and backend.request_configuration == {"test_device_ids": ["DEVICE"], "age_restricted_treatment": "teen"}, "left-out keys return to the SDK default")


func _mock_revalidates(backend: FirebaseAdmobMock) -> void:
	var direct := FirebaseRequests.new(backend)
	for call: Array in INVALID_CALLS:
		var result: FirebaseResult = await direct.send(call[0], call[1]).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "the mock also rejects %s%s" % [call[0], var_to_str(call[1])])


func _load(admob: FirebaseAdmob) -> int:
	var result := await admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit()).wait()
	check(result.ok and result.value is int and result.value > 0, "load returns a positive ad id")
	return result.value if result.ok else 0


func _on_ad_event(ad_id: int, event: String) -> void:
	_events.append({"ad_id": ad_id, "event": event, "frame": Engine.get_process_frames()})


func _event_names() -> Array:
	return _events.map(func(event: Dictionary) -> String: return event.event)


func _on_separate_frames() -> bool:
	for i in range(1, _events.size()):
		if _events[i].frame <= _events[i - 1].frame:
			return false
	return true
