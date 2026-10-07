class_name FirebaseAdmob
extends RefCounted
## Google Mobile Ads rewarded ads with UMP consent, on iOS and Android.
##
## Call request_consent() on every launch before loading ads: load_rewarded()
## fails with FirebaseResult.ERR_UNAVAILABLE until it succeeded in this launch
## with can_request_ads true. One full-screen item (ad or consent form) can be
## open at a time; another show or form request fails with FirebaseResult.ERR_BUSY.
##
## The show_rewarded() `rewarded` flag is UI feedback only. Grant rewards on your
## server from server-side verification (SSV): pass `verification` to
## show_rewarded() and credit the player when Google calls your SSV callback.
##
## Pause the game and mute audio on the "opened" ad_event and resume on
## "closed": Android keeps running the game loop behind the ad and iOS does
## not send the app to the background.

## Ad lifecycle: EVENT_OPENED, EVENT_IMPRESSION, EVENT_CLICKED,
## EVENT_REWARD_EARNED, EVENT_CLOSED or EVENT_FAILED_TO_SHOW. Google ads send
## reward_earned before closed; mediated ads may not, so the final reward is
## the show_rewarded() result.
signal ad_event(ad_id: int, event: String)

# Ad errors; the bridges map Android and iOS codes to these and keep the
# platform code and message in error_message.
const ERROR_INTERNAL := 1
const ERROR_INVALID_REQUEST := 2
const ERROR_NETWORK := 3
const ERROR_NO_FILL := 4
const ERROR_APP_ID_MISSING := 5
const ERROR_AD_EXPIRED := 6
const ERROR_AD_ALREADY_USED := 7
const ERROR_SHOW_FAILED := 8

const CONSENT_UNKNOWN := "unknown"
const CONSENT_REQUIRED := "required"
const CONSENT_NOT_REQUIRED := "not_required"
const CONSENT_OBTAINED := "obtained"

const EVENT_OPENED := "opened"
const EVENT_IMPRESSION := "impression"
const EVENT_CLICKED := "clicked"
const EVENT_REWARD_EARNED := "reward_earned"
const EVENT_CLOSED := "closed"
const EVENT_FAILED_TO_SHOW := "failed_to_show"

## Google's official rewarded test units. Real units during development can
## get the AdMob account suspended.
const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_IOS := "ca-app-pub-3940256099942544/1712485313"
## A loaded ad can be shown for one hour.
const AD_EXPIRY_MS := 3600000

const AD_UNIT_PATTERN := "^ca-app-pub-\\d{16}/\\d{10}$"
const VERIFICATION_KEYS := ["user_id", "custom_data"]
const CONSENT_OPTION_KEYS := ["debug_geography", "test_device_hashed_ids"]
const DEBUG_GEOGRAPHIES := ["eea", "other", "regulated_us_state"]
const REQUEST_CONFIGURATION_KEYS := ["test_device_ids", "max_ad_content_rating", "age_restricted_treatment"]
const MAX_AD_CONTENT_RATINGS := ["G", "PG", "T", "MA"]
const AGE_RESTRICTED_TREATMENTS := ["child", "teen"]

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.ad_event.connect(ad_event.emit)


## Updates consent information and shows the consent form when required.
## Result: {can_request_ads: bool, consent_status: CONSENT_*,
## privacy_options_required: bool}. `options` are for testing only:
## {debug_geography: "eea"|"other"|"regulated_us_state",
## test_device_hashed_ids: PackedStringArray}.
func request_consent(options: Dictionary = {}) -> FirebaseTask:
	return _send(&"request_consent", [options], validate_consent_options(options))


## Shows the privacy options form; same result as request_consent(). When
## privacy_options_required is true, Google policy requires the game to offer
## this in its settings screen.
func show_privacy_options() -> FirebaseTask:
	return _requests.send(&"show_privacy_options")


## Testing only: forgets the stored consent. Call request_consent() again
## before loading ads.
func reset_consent() -> FirebaseTask:
	return _requests.send(&"reset_consent")


## Optional, before the first load. Keys: test_device_ids (Strings),
## max_ad_content_rating ("G"|"PG"|"T"|"MA"), age_restricted_treatment
## ("child"|"teen"). Keys left out keep the SDK default (unspecified age).
func set_request_configuration(config: Dictionary) -> FirebaseTask:
	return _send(&"set_request_configuration", [config], validate_request_configuration(config))


## Loads a rewarded ad; the result is its ad_id (int > 0). The ad expires
## AD_EXPIRY_MS after loading. Use test_rewarded_ad_unit() during development.
func load_rewarded(ad_unit_id: String) -> FirebaseTask:
	return _send(&"load_rewarded", [ad_unit_id], validate_ad_unit_id(ad_unit_id))


## Shows a loaded ad once and completes when the ad closes, with
## {rewarded: bool, reward_type: String, reward_amount: int}. The ad_id is
## released afterwards. `verification` ({user_id: String, custom_data: String})
## is set on the ad before it shows and reaches your SSV callback.
## `rewarded` is UI feedback only; grant the reward from server-side verification.
func show_rewarded(ad_id: int, verification: Dictionary = {}) -> FirebaseTask:
	var reason := validate_ad_id(ad_id)
	if reason.is_empty():
		reason = validate_verification(verification)
	return _send(&"show_rewarded", [ad_id, verification], reason)


## Releases a loaded ad that will not be shown. Invalid ad ids are ignored.
func release_rewarded(ad_id: int) -> void:
	if validate_ad_id(ad_id).is_empty() and _requests.backend:
		_requests.backend.release_rewarded(ad_id)


## Google's rewarded test unit for this platform.
static func test_rewarded_ad_unit() -> String:
	return TEST_REWARDED_IOS if OS.has_feature("ios") else TEST_REWARDED_ANDROID


## The validators return "" for valid input, otherwise the reason.
static func validate_ad_unit_id(ad_unit_id: String) -> String:
	# `$` also matches before a final newline, so the match must be the whole ID.
	var found := RegEx.create_from_string(AD_UNIT_PATTERN).search(ad_unit_id)
	if found == null or found.get_string() != ad_unit_id:
		return "ad unit ID must look like ca-app-pub-<16 digits>/<10 digits>"
	return ""


static func validate_ad_id(ad_id: int) -> String:
	return "" if ad_id > 0 else "ad_id must be positive"


static func validate_verification(verification: Dictionary) -> String:
	for key in verification:
		if not key is String or key not in VERIFICATION_KEYS:
			return "verification accepts only the String keys user_id and custom_data"
		if not verification[key] is String:
			return "verification values must be Strings"
	return ""


static func validate_consent_options(options: Dictionary) -> String:
	for key in options:
		var value: Variant = options[key]
		if not key is String or key not in CONSENT_OPTION_KEYS:
			return "consent options accept only debug_geography and test_device_hashed_ids"
		if key == "debug_geography" and not (value is String and value in DEBUG_GEOGRAPHIES):
			return "debug_geography must be eea, other or regulated_us_state"
		if key == "test_device_hashed_ids" and not _is_string_list(value):
			return "test_device_hashed_ids must be a list of Strings"
	return ""


static func validate_request_configuration(config: Dictionary) -> String:
	for key in config:
		var value: Variant = config[key]
		if not key is String or key not in REQUEST_CONFIGURATION_KEYS:
			return "request configuration accepts only test_device_ids, max_ad_content_rating and age_restricted_treatment"
		if key == "test_device_ids" and not _is_string_list(value):
			return "test_device_ids must be a list of Strings"
		if key == "max_ad_content_rating" and not (value is String and value in MAX_AD_CONTENT_RATINGS):
			return "max_ad_content_rating must be G, PG, T or MA"
		if key == "age_restricted_treatment" and not (value is String and value in AGE_RESTRICTED_TREATMENTS):
			return "age_restricted_treatment must be child or teen"
	return ""


static func _is_string_list(value: Variant) -> bool:
	if value is PackedStringArray:
		return true
	return value is Array and value.all(func(item: Variant) -> bool: return item is String)


func _send(method: StringName, args: Array, reason: String) -> FirebaseTask:
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _requests.send(method, args)
