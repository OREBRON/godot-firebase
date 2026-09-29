class_name FirebaseAuthMock
extends FirebaseMockModule
## In-memory FirebaseAuthNative. Every provider signs in instantly.

signal auth_state_changed(user: Dictionary)

var _user: Dictionary = {}


func sign_in(provider: String, link: bool) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if link:
		_user.is_anonymous = false
	else:
		_user = {"uid": "mock-%s-%d" % [provider, id], "email": "", "display_name": "", "is_anonymous": provider == "anonymous"}
	_finish(id, _user.duplicate())
	auth_state_changed.emit.call_deferred(_user.duplicate())
	return id


func sign_in_play_games(_server_auth_code: String, link: bool) -> int:
	return sign_in("play_games", link)


func sign_out() -> void:
	_user = {}
	auth_state_changed.emit.call_deferred({})


func delete_user() -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		sign_out()
		_finish(id)
	return id


func get_id_token(_force_refresh: bool) -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		_finish(id, "mock-token-%s" % _user.get("uid", ""))
	return id


func current_user() -> Dictionary:
	return _user.duplicate()
