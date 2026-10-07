class_name FirebaseAdmobMock
extends FirebaseMockModule
## Memory-only rewarded ads and consent for the editor and desktop. Each mock
## is a fresh launch: consent starts unknown. Ad and consent screens stay up
## across process frames like native ones. Ad age uses the system clock unless
## a test freezes it. No ad network, SSV callback or real consent form.

signal ad_event(ad_id: int, event: String)

## Project setting read at creation: "not_required" (default) needs no consent
## form; "required" shows the form on the first request_consent(), as in the EEA.
const CONSENT_SETTING := "firebase/admob/mock_consent"
const CONSENT_MODES := ["not_required", "required"]

## The configuration accepted by the last set_request_configuration().
var request_configuration: Dictionary = {}
## The verification passed to the last shown ad.
var last_verification: Dictionary = {}

var _consent_required := false
var _consent_status := FirebaseAdmob.CONSENT_UNKNOWN
var _showing := false
var _loaded_at_ms: Dictionary[int, int] = {}
var _last_ad_id := 0
var _no_fill_next := false
var _close_early_next := false
var _reward_type := "reward"
var _reward_amount := 1
var _frozen_clock_ms := -1
var _clock_offset_ms := 0


## Tests pass `frozen_clock_ms` to pin the clock to that epoch millisecond;
## only advance_time() moves it then.
func _init(frozen_clock_ms := -1) -> void:
	_frozen_clock_ms = frozen_clock_ms
	_consent_required = _read_consent_mode() == "required"


func request_consent(options: Dictionary) -> int:
	var id := _take_id()
	var reason := FirebaseAdmob.validate_consent_options(options)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not _fail_if_busy(id) and not _fail_if_requested(id):
		if _consent_required and _consent_status != FirebaseAdmob.CONSENT_OBTAINED:
			_show_form(id)
		else:
			# Like the SDK, consent counts once the request completes.
			_answer_consent.call_deferred(id)
	return id


func show_privacy_options() -> int:
	var id := _take_id()
	if not _fail_if_busy(id) and not _fail_if_requested(id):
		if _privacy_options_required():
			_show_form(id)
		else:
			_finish(id, _consent_info())
	return id


func reset_consent() -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_consent_status = FirebaseAdmob.CONSENT_UNKNOWN
		_finish(id)
	return id


func set_request_configuration(config: Dictionary) -> int:
	var id := _take_id()
	var reason := FirebaseAdmob.validate_request_configuration(config)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not _fail_if_requested(id):
		request_configuration = config.duplicate(true)
		_finish(id)
	return id


func load_rewarded(ad_unit_id: String) -> int:
	var id := _take_id()
	var reason := FirebaseAdmob.validate_ad_unit_id(ad_unit_id)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not _can_request_ads():
		_finish_error(id, FirebaseResult.ERR_UNAVAILABLE, "request_consent() must succeed in this launch before ads load")
	elif _no_fill_next:
		_no_fill_next = false
		_finish_error(id, FirebaseAdmob.ERROR_NO_FILL, "no ad to show")
	elif not _fail_if_requested(id):
		_last_ad_id += 1
		_loaded_at_ms[_last_ad_id] = _now_ms()
		_finish(id, _last_ad_id)
	return id


func show_rewarded(ad_id: int, verification: Dictionary) -> int:
	var id := _take_id()
	var reason := FirebaseAdmob.validate_verification(verification)
	if reason.is_empty() and not _loaded_at_ms.has(ad_id):
		reason = "unknown ad_id %d; an ad is forgotten after show or release" % ad_id
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not _fail_if_busy(id) and not _fail_if_requested(id):
		_show(id, ad_id, verification)
	return id


func release_rewarded(ad_id: int) -> void:
	_loaded_at_ms.erase(ad_id)


# Test controls, deliberately excluded from the native/public SDK contract.

## Makes the next load_rewarded() fail with FirebaseAdmob.ERROR_NO_FILL.
func simulate_no_fill() -> void:
	_no_fill_next = true


## Makes the next shown ad close before its reward: no reward_earned event and
## a result with rewarded false.
func close_next_early() -> void:
	_close_early_next = true


## Sets the reward of later shows; the default is "reward", 1.
func set_mock_reward(type: String, amount: int) -> void:
	_reward_type = type
	_reward_amount = amount


## Moves the mock clock forward without waiting.
func advance_time(milliseconds: int) -> void:
	if milliseconds >= 0:
		_clock_offset_ms += milliseconds


func _read_consent_mode() -> String:
	var mode: Variant = ProjectSettings.get_setting(CONSENT_SETTING, "not_required")
	if mode is String and mode in CONSENT_MODES:
		return mode
	push_error("Firebase: %s must be \"not_required\" or \"required\"; the admob mock needs no consent" % CONSENT_SETTING)
	return "not_required"


## Fails request `id` with ERR_BUSY while an ad or consent form is showing.
func _fail_if_busy(id: int) -> bool:
	if _showing:
		_finish_error(id, FirebaseResult.ERR_BUSY, "an ad or consent form is already showing")
	return _showing


func _can_request_ads() -> bool:
	return _consent_status in [FirebaseAdmob.CONSENT_NOT_REQUIRED, FirebaseAdmob.CONSENT_OBTAINED]


func _privacy_options_required() -> bool:
	return _consent_required and _consent_status == FirebaseAdmob.CONSENT_OBTAINED


func _consent_info() -> Dictionary:
	return {"can_request_ads": _can_request_ads(), "consent_status": _consent_status, "privacy_options_required": _privacy_options_required()}


func _answer_consent(id: int) -> void:
	_consent_status = FirebaseAdmob.CONSENT_OBTAINED if _consent_required else FirebaseAdmob.CONSENT_NOT_REQUIRED
	_finish(id, _consent_info())


## The user answers the consent or privacy options form on the next frame.
func _show_form(id: int) -> void:
	_showing = true
	_on_next_frame(_close_form.bind(id))


func _close_form(id: int) -> void:
	_showing = false
	_answer_consent(id)


## Shows a loaded ad once; an expired one fails instead. Either way it is forgotten.
func _show(id: int, ad_id: int, verification: Dictionary) -> void:
	var age_ms := _now_ms() - _loaded_at_ms[ad_id]
	_loaded_at_ms.erase(ad_id)
	if age_ms > FirebaseAdmob.AD_EXPIRY_MS:
		ad_event.emit.call_deferred(ad_id, FirebaseAdmob.EVENT_FAILED_TO_SHOW)
		_finish_error(id, FirebaseAdmob.ERROR_AD_EXPIRED, "the ad expired one hour after loading")
		return
	var result := _take_reward()
	var events := [FirebaseAdmob.EVENT_OPENED, FirebaseAdmob.EVENT_IMPRESSION, FirebaseAdmob.EVENT_CLOSED]
	if result.rewarded:
		events.insert(2, FirebaseAdmob.EVENT_REWARD_EARNED)
	last_verification = verification.duplicate()
	_showing = true
	_on_next_frame(_play.bind(id, ad_id, events, result))


## Consumes close_next_early() and returns the next show's result.
func _take_reward() -> Dictionary:
	var rewarded := not _close_early_next
	_close_early_next = false
	if not rewarded:
		return {"rewarded": false, "reward_type": "", "reward_amount": 0}
	return {"rewarded": true, "reward_type": _reward_type, "reward_amount": _reward_amount}


## Emits the first of `events`, one per frame; the show completes after the last.
func _play(id: int, ad_id: int, events: Array, result: Dictionary) -> void:
	ad_event.emit(ad_id, events[0])
	if events.size() > 1:
		_on_next_frame(_play.bind(id, ad_id, events.slice(1), result))
	else:
		_showing = false
		_finish(id, result)


func _on_next_frame(step: Callable) -> void:
	(Engine.get_main_loop() as SceneTree).process_frame.connect(step, CONNECT_ONE_SHOT)


func _now_ms() -> int:
	var base := _frozen_clock_ms if _frozen_clock_ms >= 0 else int(Time.get_unix_time_from_system() * 1000)
	return base + _clock_offset_ms
