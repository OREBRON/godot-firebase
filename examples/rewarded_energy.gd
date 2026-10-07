extends Node
## Rewarded ad -> energy, granted by the server (templates/admob_ssv).
## Attach to a menu or gameplay controller with the Firebase autoload installed.
## The client never adds energy: `rewarded: true` is the SDK's report, not the
## grant. Energy arrives through users/<uid>, which only the reward function
## writes after verifying Google's signed callback.
##
## No callback reaches the editor or desktop. While AdMob and Firestore are both
## mocks, a debug-only simulator writes the function's increment to the
## Firestore mock instead. It is game debug code, not part of the SDK.

signal energy_changed(energy: int)
## True when an ad is loaded and energy is below the cap: enable the button.
signal ad_ready_changed(available: bool)
## "processing" after a rewarded ad, "delayed" after reward_timeout_sec,
## "" once the server's energy arrives. A delayed reward still arrives later.
signal reward_status_changed(status: String)

const MASTER_BUS := 0

## Your rewarded ad unit. Empty uses Google's test unit; never show real ads
## while developing. SSV needs your own unit on a registered test device.
@export var ad_unit_id := ""
## Must match the ad unit's customData in the function's CONFIG.
@export var custom_data := "energy"
## Mirror of the function's maxAmount and energyCap (button label, simulator).
@export var reward_per_ad := 5
@export var energy_cap := 100
@export var reward_timeout_sec := 20.0
@export var load_retry_sec := 30.0
@export var simulated_delay_sec := 1.0

## Show a "Privacy options" button in settings while true (Google policy).
var privacy_options_required := false

var _firebase: Node
# Firebase.admob (FirebaseAdmob); module properties are RefCounted.
var _admob: RefCounted
var _auth: FirebaseAuth
var _firestore: FirebaseFirestore
var _uid := ""
var _listener_id := 0
var _ad_id := 0
var _ready_to_watch := false
var _energy := 0
var _energy_at_show := 0
var _status := ""
var _status_generation := 0
var _paused_by_ad := false
var _was_paused := false
var _was_muted := false


func _ready() -> void:
	# Ad events must still arrive while the ad pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_firebase = get_node_or_null("/root/Firebase")
	if _firebase == null:
		push_error("Rewarded energy needs the Firebase autoload")
		return
	_admob = _firebase.get("admob")
	_auth = _firebase.get("auth")
	_firestore = _firebase.get("firestore")
	if _admob == null or _auth == null or _firestore == null:
		push_error("Rewarded energy needs the admob, auth and firestore modules")
		return
	_admob.ad_event.connect(_on_ad_event)
	var signed_in := await _sign_in()
	if not signed_in or not is_inside_tree():
		return
	_listener_id = _firestore.listen_doc("users/%s" % _uid, _on_user_changed)
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


## The "Watch ad: +5 energy" button.
func watch_ad_for_energy() -> void:
	if _ad_id == 0:
		return
	var ad := _ad_id
	_ad_id = 0
	_update_ready()
	_energy_at_show = _energy
	# The function grants to user_id; custom_data must match its allowlist.
	var shown: FirebaseResult = await _admob.show_rewarded(ad, {"user_id": _uid, "custom_data": custom_data}).wait()
	if not is_inside_tree():
		return
	_resume_after_ad()
	if not shown.ok:
		push_warning("Rewarded ad not shown: " + shown.error_message)
	elif shown.value.rewarded:
		_wait_for_server_reward()
	_load_ad()


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
		_update_ready()
		return
	push_warning("Rewarded ad did not load: " + loaded.error_message)
	await get_tree().create_timer(load_retry_sec).timeout
	if is_inside_tree():
		_load_ad()


func _wait_for_server_reward() -> void:
	if _energy > _energy_at_show:
		return
	_set_status("processing")
	var generation := _status_generation
	await get_tree().create_timer(reward_timeout_sec).timeout
	if generation == _status_generation and is_inside_tree():
		# SSV may take longer (Google retries); the listener still shows it.
		_set_status("delayed")


func _on_user_changed(result: FirebaseResult) -> void:
	if not result.ok:
		push_warning("Energy listener failed: " + result.error_message)
		return
	var data: Dictionary = result.value.data if result.value.exists else {}
	_energy = int(data.get("energy", 0))
	energy_changed.emit(_energy)
	if not _status.is_empty() and _energy > _energy_at_show:
		_set_status("")
	_update_ready()


func _on_ad_event(_event_ad_id: int, event: String) -> void:
	match event:
		"opened":
			_pause_for_ad()
		"closed", "failed_to_show":
			_resume_after_ad()
		"reward_earned":
			if _is_editor_simulation():
				_simulate_server_reward()


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


func _update_ready() -> void:
	var available := _ad_id != 0 and _energy < energy_cap
	if available != _ready_to_watch:
		_ready_to_watch = available
		ad_ready_changed.emit(available)


func _set_status(status: String) -> void:
	_status_generation += 1
	if status != _status:
		_status = status
		reward_status_changed.emit(status)


# Both mocks: nothing here can reach real AdMob callbacks or real Firestore data.
func _is_editor_simulation() -> bool:
	return _firebase.is_mock("admob") and _firebase.is_mock("firestore")


# Stands in for the reward function: up to reward_per_ad, never past energy_cap.
func _simulate_server_reward() -> void:
	await get_tree().create_timer(simulated_delay_sec).timeout
	var amount := mini(reward_per_ad, maxi(0, energy_cap - _energy))
	if not is_inside_tree() or amount == 0:
		return
	var path := "users/%s" % _uid
	var written: FirebaseResult = await _firestore.set_doc(path, {"energy": FirebaseValue.increment(amount)}, true).wait()
	if not written.ok:
		push_warning("Simulated reward failed: " + written.error_message)
