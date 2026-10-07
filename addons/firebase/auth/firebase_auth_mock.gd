class_name FirebaseAuthMock
extends FirebaseMockModule
## In-memory auth accounts live for this backend instance only.

signal auth_state_changed(user: Dictionary)

# firebase::auth::kAuthErrorCredentialAlreadyInUse (pinned C++ SDK).
const CREDENTIAL_ALREADY_IN_USE := 10

var _user: Dictionary = {}
var _accounts: Dictionary = {}
var _provider_accounts: Dictionary = {}
var _selected_accounts: Dictionary = {}
var _pending: Dictionary = {}
var _delayed: Array[Dictionary] = []
var _delay_next := false
var _generation := 0
var _closed := false


func _init() -> void:
	# Native reports the restored user (or {}) once its SDK listener is
	# registered; deferred so the API created right after this can receive it.
	auth_state_changed.emit.call_deferred(current_user())


func sign_in(provider: String, link: bool) -> int:
	var id := _take_id()
	if _closed:
		_finish_error(id, FirebaseResult.ERR_UNAVAILABLE, "auth backend is shut down")
	elif not _pending.is_empty():
		_finish_error(id, FirebaseResult.ERR_BUSY, "another auth operation is running")
	elif link and _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "link needs a signed-in user")
	elif provider not in ["anonymous", "apple", "game_center", "google", "play_games", "play_games_platform"]:
		_finish_error(id, FirebaseResult.ERR_UNSUPPORTED, "unknown auth provider")
	elif link and provider == "anonymous":
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "cannot link an anonymous account")
	elif not _fail_if_requested(id):
		var canonical := "play_games" if provider == "play_games_platform" else provider
		_pending = {"id": id, "provider": canonical, "link": link, "uid": _user.get("uid", ""), "generation": _generation, "account": _selected_accounts.get(canonical, "default")}
		var operation := _pending.duplicate()
		if _delay_next:
			_delay_next = false
			_delayed.append(operation)
		else:
			_complete_sign_in.call_deferred(operation)
	return id


func sign_in_play_games(server_auth_code: String, link: bool) -> int:
	if server_auth_code.is_empty():
		var id := _take_id()
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "Play Games server auth code is required")
		return id
	return sign_in("play_games", link)


func _complete_sign_in(operation: Dictionary) -> void:
	if _closed or operation.generation != _generation or _pending.get("id") != operation.id:
		return
	_pending = {}
	if operation.uid != _user.get("uid", ""):
		_finish_error(operation.id, FirebaseResult.ERR_CANCELLED, "signed-in user changed")
		return
	if operation.provider == "anonymous" and _user.get("is_anonymous", false):
		# The SDK returns the signed-in anonymous user; its uid stays, so no
		# auth state change. Any other user is replaced by a new anonymous one.
		_finish(operation.id, _user.duplicate())
		return
	var key: String = operation.provider + ":" + operation.account
	var existing_uid: String = _provider_accounts.get(key, "")
	if operation.link and not existing_uid.is_empty() and existing_uid != operation.uid:
		_finish_error(operation.id, CREDENTIAL_ALREADY_IN_USE, "credential belongs to another account")
		return
	if operation.link:
		_user.is_anonymous = false
	elif not existing_uid.is_empty():
		_user = _accounts[existing_uid].duplicate()
	else:
		_user = {"uid": "mock-%s-%d" % [operation.provider, operation.id], "email": "", "display_name": "", "is_anonymous": operation.provider == "anonymous"}
	_accounts[_user.uid] = _user.duplicate()
	if operation.provider != "anonymous":
		_provider_accounts[key] = _user.uid
	_finish(operation.id, _user.duplicate())
	auth_state_changed.emit.call_deferred(_user.duplicate())


func _cancel_pending() -> void:
	_generation += 1
	if not _pending.is_empty():
		_finish_error(_pending.id, FirebaseResult.ERR_CANCELLED, "auth operation was cancelled")
		_pending = {}


func sign_out() -> void:
	_cancel_pending()
	_user = {}
	auth_state_changed.emit.call_deferred({})


func delete_user() -> int:
	var id := _take_id()
	if _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "no signed-in user")
	elif not _fail_if_requested(id):
		for key in _provider_accounts.keys():
			if _provider_accounts[key] == _user.uid:
				_provider_accounts.erase(key)
		_accounts.erase(_user.uid)
		sign_out()
		_finish(id)
	return id


func get_id_token(_force_refresh: bool) -> int:
	var id := _take_id()
	if _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "no signed-in user")
	elif not _fail_if_requested(id):
		_finish(id, "mock-token-%s" % _user.uid)
	return id


func current_user() -> Dictionary:
	return _user.duplicate()


# Test controls, deliberately excluded from the native/public SDK contract.
func delay_next_sign_in() -> void:
	_delay_next = true


func complete_pending_sign_in() -> void:
	if not _delayed.is_empty():
		_complete_sign_in(_delayed.pop_front())


func set_provider_account(provider: String, account: String) -> void:
	_selected_accounts[provider] = account


func shutdown_for_test() -> void:
	_cancel_pending()
	_closed = true
