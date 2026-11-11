class_name FirebaseAuthMock
extends FirebaseMockModule
## In-memory auth accounts live for this backend instance only. The first email
## sign-in creates its account; the same custom token string returns the same account.

signal auth_state_changed(user: Dictionary)

# firebase::auth::AuthError values (pinned C++ SDK).
const CREDENTIAL_ALREADY_IN_USE := 10
const NO_SUCH_PROVIDER := 16
const USER_MISMATCH := 22

# What an operation does with its credential; also used in error messages.
const SIGN_IN := "sign_in"
const LINK := "link"
const REAUTHENTICATE := "reauthenticate"
# Providers sign_in() accepts; email and custom token name their account instead.
const PLATFORM_PROVIDERS := ["anonymous", "apple", "game_center", "google", "play_games", "play_games_platform"]
# UserInfo::provider_id() of each provider; custom token users have none.
const PROVIDER_IDS := {"apple": "apple.com", "game_center": "gc.apple.com", "google": "google.com", "play_games": "playgames.google.com", "password": "password"}

## Project setting read at creation: "" (default) allows every provider;
## "android" or "ios" fails sign-in like the native addon on that platform.
const PLATFORM_SETTING := "firebase/auth/mock_platform"
const PLATFORM_NAMES := {"android": "Android", "ios": "iOS"}
# Providers FirebaseAuth passes to sign_in() that src/auth/platform/ rejects.
const UNSUPPORTED_PROVIDERS := {"android": ["apple", "game_center"], "ios": ["play_games_platform"]}

var _user: Dictionary = {}
var _accounts: Dictionary = {}
var _provider_accounts: Dictionary = {}
var _selected_accounts: Dictionary = {}
var _pending: Dictionary = {}
var _delayed: Array[Dictionary] = []
var _delay_next := false
var _generation := 0
var _closed := false
var _platform := ""
## Test-observable startup option; the mock never connects to an emulator.
var emulator_host := ""


func _init() -> void:
	_platform = _read_platform()
	# Native reports the restored user (or {}) once its SDK listener is
	# registered; deferred so the API created right after this can receive it.
	auth_state_changed.emit.call_deferred(current_user())


func initialize(emulator_host: String = "") -> int:
	self.emulator_host = emulator_host
	return OK


func sign_in(provider: String, link: bool) -> int:
	return _start(provider, LINK if link else SIGN_IN)


func reauthenticate(provider: String) -> int:
	return _start(provider, REAUTHENTICATE)


func sign_in_with_custom_token(token: String) -> int:
	if token.is_empty():
		return _fail(FirebaseResult.ERR_INVALID_ARGUMENT, "custom token is required")
	return _start("custom", SIGN_IN, token)


func sign_in_with_email(email: String, password: String) -> int:
	return _start_email(email, password, SIGN_IN)


func reauthenticate_with_email(email: String, password: String) -> int:
	return _start_email(email, password, REAUTHENTICATE)


func _start_email(email: String, password: String, mode: String) -> int:
	var reason := FirebaseAuth.validate_email(email, password)
	if not reason.is_empty():
		return _fail(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _start("password", mode, email)


# An empty `account` lets the platform UI pick the account set_provider_account() selected.
func _start(provider: String, mode: String, account := "") -> int:
	var id := _take_id()
	if _closed:
		_finish_error(id, FirebaseResult.ERR_UNAVAILABLE, "auth backend is shut down")
	elif not _pending.is_empty():
		_finish_error(id, FirebaseResult.ERR_BUSY, "another auth operation is running")
	elif mode != SIGN_IN and _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "%s needs a signed-in user" % mode)
	elif account.is_empty() and provider not in PLATFORM_PROVIDERS:
		_finish_error(id, FirebaseResult.ERR_UNSUPPORTED, "unknown auth provider")
	elif mode != SIGN_IN and provider == "anonymous":
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "cannot %s an anonymous account" % mode)
	elif provider in UNSUPPORTED_PROVIDERS.get(_platform, []):
		_finish_error(id, FirebaseResult.ERR_UNSUPPORTED, "%s sign-in is not supported on %s" % [provider, PLATFORM_NAMES[_platform]])
	elif not _fail_if_requested(id):
		var canonical := "play_games" if provider == "play_games_platform" else provider
		if account.is_empty():
			account = _selected_accounts.get(canonical, "default")
		_pending = {"id": id, "provider": canonical, "mode": mode, "uid": _user.get("uid", ""), "generation": _generation, "account": account}
		var operation := _pending.duplicate()
		if _delay_next:
			_delay_next = false
			_delayed.append(operation)
		else:
			_complete_sign_in.call_deferred(operation)
	return id


func sign_in_play_games(server_auth_code: String, link: bool) -> int:
	if server_auth_code.is_empty():
		return _fail(FirebaseResult.ERR_INVALID_ARGUMENT, "Play Games server auth code is required")
	if _platform == "ios":
		return _fail(FirebaseResult.ERR_UNSUPPORTED, "Play Games sign-in requires Android")
	return sign_in("play_games", link)


func _fail(code: int, message: String) -> int:
	var id := _take_id()
	_finish_error(id, code, message)
	return id


func _read_platform() -> String:
	var platform: Variant = ProjectSettings.get_setting(PLATFORM_SETTING, "")
	if platform is String and (platform.is_empty() or PLATFORM_NAMES.has(platform)):
		return platform
	push_error("Firebase: %s must be \"\", \"android\" or \"ios\"; the auth mock allows every provider" % PLATFORM_SETTING)
	return ""


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
		_finish(operation.id, current_user())
		return
	var key: String = operation.provider + ":" + operation.account
	var existing_uid: String = _provider_accounts.get(key, "")
	if operation.mode == REAUTHENTICATE:
		if existing_uid == operation.uid:
			_finish(operation.id)
		else:
			_finish_error(operation.id, USER_MISMATCH, "credential belongs to another account")
		return
	if operation.mode == LINK and not existing_uid.is_empty() and existing_uid != operation.uid:
		_finish_error(operation.id, CREDENTIAL_ALREADY_IN_USE, "credential belongs to another account")
		return
	if operation.mode == LINK:
		_user.is_anonymous = false
	elif not existing_uid.is_empty():
		_user = _accounts[existing_uid].duplicate()
	else:
		var email: String = operation.account if operation.provider == "password" else ""
		_user = {"uid": "mock-%s-%d" % [operation.provider, operation.id], "email": email, "display_name": "", "photo_url": "", "is_anonymous": operation.provider == "anonymous"}
	_accounts[_user.uid] = _user.duplicate()
	if operation.provider != "anonymous":
		_provider_accounts[key] = _user.uid
	_finish(operation.id, current_user())
	auth_state_changed.emit.call_deferred(current_user())


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


func revoke_apple_token() -> int:
	var id := _take_id()
	var apple := _has_provider("apple")
	if _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "no signed-in user")
	elif not _pending.is_empty():
		_finish_error(id, FirebaseResult.ERR_BUSY, "another auth operation is running")
	elif apple and "apple" in UNSUPPORTED_PROVIDERS.get(_platform, []):
		_finish_error(id, FirebaseResult.ERR_UNSUPPORTED, "apple sign-in is not supported on %s" % PLATFORM_NAMES[_platform])
	# fail_next() stands for a cancelled Apple sheet or a failed revocation; other accounts show no UI.
	elif not apple or not _fail_if_requested(id):
		_finish(id, apple)
	return id


func _has_provider(provider: String) -> bool:
	return PROVIDER_IDS[provider] in _providers(_user.get("uid", ""))


func _providers(uid: String) -> Array:
	var providers := []
	for key: String in _provider_accounts:
		var provider := key.get_slice(":", 0)
		if _provider_accounts[key] == uid and PROVIDER_IDS.has(provider):
			providers.append(PROVIDER_IDS[provider])
	return providers


func unlink_provider(provider_id: String) -> int:
	var id := _take_id()
	if _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "no signed-in user")
	elif provider_id.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "provider ID is required")
	elif provider_id not in _providers(_user.uid):
		_finish_error(id, NO_SUCH_PROVIDER, "user is not linked to this provider")
	elif not _fail_if_requested(id):
		for key: String in _provider_accounts.keys():
			if _provider_accounts[key] == _user.uid and PROVIDER_IDS.get(key.get_slice(":", 0)) == provider_id:
				_provider_accounts.erase(key)
		_finish(id)
	return id


func update_profile(profile: Dictionary) -> int:
	var id := _take_id()
	var reason := FirebaseAuth.validate_profile(profile)
	if _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "no signed-in user")
	elif not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not _fail_if_requested(id):
		_user.merge(profile, true)
		_accounts[_user.uid] = _user.duplicate()
		_finish(id)
	return id


func reload_user() -> int:
	var id := _take_id()
	if _user.is_empty():
		_finish_error(id, FirebaseResult.ERR_NO_USER, "no signed-in user")
	elif not _fail_if_requested(id):
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
	var user := _user.duplicate()
	if not user.is_empty():
		user.providers = _providers(user.uid)
	return user


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
