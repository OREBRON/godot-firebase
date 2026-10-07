extends Node
## Rewarded ads -> energy, lives, coins or any reward in the server's CONFIG,
## granted by the server (templates/admob_ssv). Attach to a menu or gameplay
## controller with the Firebase autoload installed.
##
## The client never adds rewards: `rewarded: true` is the SDK's report, not the
## grant. Balances arrive through wallets/<uid>, which only the reward function
## writes after verifying Google's signed callback; spending goes through the
## spendReward function.
##
## No callback reaches the editor or desktop. While AdMob and Firestore are both
## mocks, a debug-only simulator writes the functions' changes to the Firestore
## mock instead. It is game debug code, not part of the SDK.

## Balances by reward name, e.g. {"energy": 12, "lives": 3, "coins": 150}.
signal balances_changed(balances: Dictionary)
## True when an ad is loaded: enable the "watch ad" buttons (see can_watch_for()).
signal ad_ready_changed(available: bool)
## "processing" after a rewarded ad, "delayed" after reward_timeout_sec,
## "" once the server's grant arrives. A delayed reward still arrives later.
signal reward_status_changed(reward: String, status: String)

const MASTER_BUS := 0
## Firebase Functions error code for a short balance (FAILED_PRECONDITION).
const ERROR_FAILED_PRECONDITION := 9

## Your rewarded ad unit. Empty uses Google's test unit; never show real ads
## while developing. SSV needs your own unit on a registered test device.
@export var ad_unit_id := ""
## Mirror of the function's CONFIG.rewards amounts and caps (0 = no cap), for
## button labels, can_watch_for() and the editor simulator.
@export var reward_amounts := {"energy": 5, "lives": 1, "coins": 50}
@export var reward_caps := {"energy": 100, "lives": 5, "coins": 0}
@export var reward_timeout_sec := 20.0
@export var load_retry_sec := 30.0
@export var simulated_delay_sec := 1.0

## Show a "Privacy options" button in settings while true (Google policy).
var privacy_options_required := false
var balances: Dictionary = {}

var _firebase: Node
# Firebase.admob (FirebaseAdmob); module properties are RefCounted.
var _admob: RefCounted
var _auth: FirebaseAuth
var _firestore: FirebaseFirestore
var _functions: FirebaseFunctions
var _uid := ""
var _listener_id := 0
var _ad_id := 0
var _showing_reward := ""
var _balance_at_show := 0
var _status := {}
var _status_generation := 0
var _paused_by_ad := false
var _was_paused := false
var _was_muted := false


func _ready() -> void:
	# Ad events must still arrive while the ad pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_firebase = get_node_or_null("/root/Firebase")
	if _firebase == null:
		push_error("Rewarded ads need the Firebase autoload")
		return
	_admob = _firebase.get("admob")
	_auth = _firebase.get("auth")
	_firestore = _firebase.get("firestore")
	_functions = _firebase.get("functions")
	if _admob == null or _auth == null or _firestore == null or _functions == null:
		push_error("Rewarded ads need the admob, auth, firestore and functions modules")
		return
	_admob.ad_event.connect(_on_ad_event)
	var signed_in := await _sign_in()
	if not signed_in or not is_inside_tree():
		return
	_listener_id = _firestore.listen_doc("wallets/%s" % _uid, _on_wallet_changed)
	# Every launch asks UMP before the first ad request.
	var consent: FirebaseResult = await _admob.request_consent().wait()
	if not is_inside_tree():
		return
	if not consent.ok:
		push_warning("Consent update failed; no ads this session: " + consent.error_message)
		return
	privacy_options_required = consent.value.privacy_options_required
	if consent.value.can_request_ads:
		_load_ad()


## True when an ad is loaded and `reward` is below its cap.
func can_watch_for(reward: String) -> bool:
	var cap: int = reward_caps.get(reward, 0)
	return _ad_id != 0 and (cap == 0 or balance(reward) < cap)


func balance(reward: String) -> int:
	return int(balances.get(reward, 0))


## A "Watch ad: +1 life" button calls watch_ad_for("lives"). The server checks
## the name against the ad unit's allowed rewards and sets the amount.
func watch_ad_for(reward: String) -> void:
	if not can_watch_for(reward) or not _showing_reward.is_empty():
		return
	var ad := _ad_id
	_ad_id = 0
	ad_ready_changed.emit(false)
	_showing_reward = reward
	_balance_at_show = balance(reward)
	# The function grants to user_id; custom_data names the reward.
	var shown: FirebaseResult = await _admob.show_rewarded(ad, {"user_id": _uid, "custom_data": reward}).wait()
	_showing_reward = ""
	if not is_inside_tree():
		return
	_resume_after_ad()
	if not shown.ok:
		push_warning("Rewarded ad not shown: " + shown.error_message)
	elif shown.value.rewarded:
		_wait_for_server_reward(reward)
	_load_ad()


## Spends through the spendReward function; fails with
## ERROR_FAILED_PRECONDITION when the balance is too low.
func spend(reward: String, amount: int) -> FirebaseResult:
	if _is_editor_simulation():
		return await _simulate_spend(reward, amount)
	return await _functions.call_function("spendReward", {"reward": reward, "amount": amount}).wait()


## The settings button shown while privacy_options_required is true.
func open_privacy_options() -> void:
	var consent: FirebaseResult = await _admob.show_privacy_options().wait()
	if consent.ok:
		privacy_options_required = consent.value.privacy_options_required
	else:
		push_warning("Privacy options failed: " + consent.error_message)


func _exit_tree() -> void:
	_status_generation += 1
	_resume_after_ad()
	if _firestore and _listener_id != 0:
		_firestore.remove_listener(_listener_id)
		_listener_id = 0
	if _admob:
		if _admob.ad_event.is_connected(_on_ad_event):
			_admob.ad_event.disconnect(_on_ad_event)
		if _ad_id != 0:
			_admob.release_rewarded(_ad_id)
			_ad_id = 0


# The game usually signs in earlier; anonymous sign-in keeps the example whole.
func _sign_in() -> bool:
	if not _auth.is_signed_in():
		var signed_in: FirebaseResult = await _auth.sign_in_anonymously().wait()
		if not signed_in.ok:
			push_warning("Sign-in failed: " + signed_in.error_message)
			return false
	_uid = _auth.current_user().get("uid", "")
	return not _uid.is_empty()


func _load_ad() -> void:
	var unit: String = ad_unit_id if not ad_unit_id.is_empty() else _admob.test_rewarded_ad_unit()
	var loaded: FirebaseResult = await _admob.load_rewarded(unit).wait()
	if not is_inside_tree():
		if loaded.ok:
			_admob.release_rewarded(loaded.value)
		return
	if loaded.ok:
		_ad_id = loaded.value
		ad_ready_changed.emit(true)
		return
	push_warning("Rewarded ad did not load: " + loaded.error_message)
	await get_tree().create_timer(load_retry_sec).timeout
	if is_inside_tree():
		_load_ad()


func _wait_for_server_reward(reward: String) -> void:
	if balance(reward) > _balance_at_show:
		return
	_set_status(reward, "processing")
	var generation := _status_generation
	await get_tree().create_timer(reward_timeout_sec).timeout
	if generation == _status_generation and is_inside_tree():
		# SSV may take longer (Google retries); the listener still shows it.
		_set_status(reward, "delayed")


func _on_wallet_changed(result: FirebaseResult) -> void:
	if not result.ok:
		push_warning("Wallet listener failed: " + result.error_message)
		return
	var previous := balances
	balances = result.value.data if result.value.exists else {}
	balances_changed.emit(balances)
	for reward: String in _status.keys():
		if balance(reward) > int(previous.get(reward, 0)):
			_set_status(reward, "")


func _on_ad_event(_event_ad_id: int, event: String) -> void:
	match event:
		"opened":
			_pause_for_ad()
		"closed", "failed_to_show":
			_resume_after_ad()
		"reward_earned":
			if _is_editor_simulation():
				_simulate_server_reward(_showing_reward)


# Fullscreen ads do not pause Godot on iOS, and Android keeps the game loop running.
func _pause_for_ad() -> void:
	if _paused_by_ad:
		return
	_paused_by_ad = true
	_was_paused = get_tree().paused
	_was_muted = AudioServer.is_bus_mute(MASTER_BUS)
	get_tree().paused = true
	AudioServer.set_bus_mute(MASTER_BUS, true)


func _resume_after_ad() -> void:
	if not _paused_by_ad:
		return
	_paused_by_ad = false
	get_tree().paused = _was_paused
	AudioServer.set_bus_mute(MASTER_BUS, _was_muted)


func _set_status(reward: String, status: String) -> void:
	_status_generation += 1
	if status.is_empty():
		_status.erase(reward)
	else:
		_status[reward] = status
	reward_status_changed.emit(reward, status)


# Both mocks: nothing here can reach real AdMob callbacks or real Firestore data.
func _is_editor_simulation() -> bool:
	return _firebase.is_mock("admob") and _firebase.is_mock("firestore")


# Stands in for the reward function: reward_amounts[reward], never past its cap.
func _simulate_server_reward(reward: String) -> void:
	await get_tree().create_timer(simulated_delay_sec).timeout
	var cap: int = reward_caps.get(reward, 0)
	var amount: int = reward_amounts.get(reward, 0)
	if cap > 0:
		amount = mini(amount, maxi(0, cap - balance(reward)))
	if not is_inside_tree() or amount == 0:
		return
	var written: FirebaseResult = await _firestore.set_doc("wallets/%s" % _uid, {reward: FirebaseValue.increment(amount)}, true).wait()
	if not written.ok:
		push_warning("Simulated reward failed: " + written.error_message)


# Stands in for spendReward against the Firestore mock.
func _simulate_spend(reward: String, amount: int) -> FirebaseResult:
	if amount < 1 or not reward_amounts.has(reward):
		return FirebaseResult.failure(FirebaseResult.ERR_INVALID_ARGUMENT, "unknown reward or amount")
	if balance(reward) < amount:
		return FirebaseResult.failure(ERROR_FAILED_PRECONDITION, "not enough " + reward)
	# The wallet listener may update balances before the write task completes.
	var remaining := balance(reward) - amount
	var written: FirebaseResult = await _firestore.set_doc("wallets/%s" % _uid, {reward: FirebaseValue.increment(-amount)}, true).wait()
	if not written.ok:
		return written
	return FirebaseResult.success({"reward": reward, "balance": remaining})
