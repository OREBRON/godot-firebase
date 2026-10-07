extends FirebaseTest
## firebase/admob/mock_consent decides whether the admob mock shows a consent
## form. Consent is per mock (per launch) and gates load_rewarded().

const SETTING := "firebase/admob/mock_consent"
const UNKNOWN := {"can_request_ads": false, "consent_status": "unknown", "privacy_options_required": false}
const NOT_REQUIRED := {"can_request_ads": true, "consent_status": "not_required", "privacy_options_required": false}
const OBTAINED := {"can_request_ads": true, "consent_status": "obtained", "privacy_options_required": true}

var _errors := ErrorLog.new()


class ErrorLog extends Logger:
	var messages: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(code + rationale)


func _run() -> void:
	if ProjectSettings.has_setting(SETTING):
		ProjectSettings.clear(SETTING)
	var firebase := mock_firebase({"admob": FirebaseAdmobMock.new()})
	await _not_required(firebase, "unset")
	ProjectSettings.set_setting(SETTING, "not_required")
	await _not_required(firebase, "not_required")
	ProjectSettings.set_setting(SETTING, "required")
	await _required(firebase)
	OS.add_logger(_errors)
	for invalid in ["sometimes", "", 1]:
		ProjectSettings.set_setting(SETTING, invalid)
		firebase.setup({"admob": FirebaseAdmobMock.new()})
		var result: FirebaseResult = await firebase.admob.request_consent().wait()
		check(result.ok and result.value == NOT_REQUIRED, "invalid mock_consent %s falls back to not_required" % var_to_str(invalid))
	OS.remove_logger(_errors)
	check(_errors.messages.filter(func(message: String) -> bool: return message.contains(SETTING)).size() == 3, "invalid mock_consent reports an error")
	ProjectSettings.clear(SETTING)


func _not_required(firebase: Node, label: String) -> void:
	firebase.setup({"admob": FirebaseAdmobMock.new()})
	var admob: FirebaseAdmob = firebase.admob
	var backend: FirebaseAdmobMock = firebase.backends.admob
	var result := await admob.show_privacy_options().wait()
	check(result.ok and result.value == UNKNOWN, label + ": consent is unknown before request_consent")
	backend.fail_next(FirebaseAdmob.ERROR_INTERNAL, "consent info update failed")
	result = await admob.request_consent().wait()
	check(not result.ok and result.error_code == FirebaseAdmob.ERROR_INTERNAL, label + ": consent errors keep their code")
	result = await _load(admob)
	check(not result.ok and result.error_code == FirebaseResult.ERR_UNAVAILABLE, label + ": a failed consent request does not allow ads")
	for task: FirebaseTask in [admob.request_consent(), admob.request_consent()]:
		result = await task.wait()
		check(result.ok and result.value == NOT_REQUIRED, label + ": consent needs no form, so requests do not block each other")
	check((await _load(admob)).ok, label + ": ads load after request_consent")
	for task: FirebaseTask in [admob.show_privacy_options(), admob.show_privacy_options()]:
		result = await task.wait()
		check(result.ok and result.value == NOT_REQUIRED, label + ": privacy options succeed without a form")
	result = await admob.reset_consent().wait()
	check(result.ok and result.value == null, label + ": reset_consent completes without a value")
	result = await _load(admob)
	check(not result.ok and result.error_code == FirebaseResult.ERR_UNAVAILABLE, label + ": reset requires request_consent again")


func _required(firebase: Node) -> void:
	firebase.setup({"admob": FirebaseAdmobMock.new()})
	var admob: FirebaseAdmob = firebase.admob
	var frames := [0]
	var count_frame := func() -> void: frames[0] += 1
	process_frame.connect(count_frame)
	var form := admob.request_consent()
	for task: FirebaseTask in [admob.request_consent(), admob.show_privacy_options()]:
		var busy := await task.wait()
		check(not busy.ok and busy.error_code == FirebaseResult.ERR_BUSY, "requests fail while the consent form shows")
	var result := await form.wait()
	check(result.ok and result.value == OBTAINED, "the first request shows the form and obtains consent")
	check(frames[0] > 0, "the consent form stays up until a later frame")
	process_frame.disconnect(count_frame)
	result = await _load(admob)
	check(result.ok, "ads load after consent is obtained")
	var ad: int = result.value if result.ok else 0
	for task: FirebaseTask in [admob.request_consent(), admob.request_consent()]:
		result = await task.wait()
		check(result.ok and result.value == OBTAINED, "later requests return obtained without a form")
	var privacy := admob.show_privacy_options()
	result = await admob.show_rewarded(ad).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_BUSY, "ads wait for the privacy options form")
	result = await privacy.wait()
	check(result.ok and result.value == OBTAINED, "the privacy options form returns the consent information")
	await admob.reset_consent().wait()
	result = await _load(admob)
	check(not result.ok and result.error_code == FirebaseResult.ERR_UNAVAILABLE, "reset forgets the obtained consent")
	form = admob.request_consent()
	result = await admob.show_rewarded(ad).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_BUSY, "after reset the consent form shows again")
	check((await form.wait()).value == OBTAINED, "the form obtains consent again")
	check((await admob.show_rewarded(ad).wait()).ok, "the ad survives the busy rejections")


func _load(admob: FirebaseAdmob) -> FirebaseResult:
	return await admob.load_rewarded(FirebaseAdmob.test_rewarded_ad_unit()).wait()
