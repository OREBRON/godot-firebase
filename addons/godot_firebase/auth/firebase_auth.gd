class_name FirebaseAuth
extends RefCounted
## Firebase Authentication API.
##
## Users are dictionaries: {uid, email, display_name, is_anonymous}.
## An empty dictionary means nobody is signed in.

signal state_changed(user: Dictionary)

const ANONYMOUS := "anonymous"
const GAME_CENTER := "game_center"
const APPLE := "apple"

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests
	if _requests.backend:
		_requests.backend.auth_state_changed.connect(state_changed.emit)


func sign_in_anonymously() -> FirebaseTask:
	return _sign_in(ANONYMOUS, false)


## Needs the Game Center entitlement. Shows Apple's sign-in sheet when required.
func sign_in_with_game_center() -> FirebaseTask:
	return _sign_in(GAME_CENTER, false)


## Needs the Sign in with Apple entitlement.
func sign_in_with_apple() -> FirebaseTask:
	return _sign_in(APPLE, false)


## Keeps the current (usually anonymous) uid and its data.
func link_with_game_center() -> FirebaseTask:
	return _sign_in(GAME_CENTER, true)


func link_with_apple() -> FirebaseTask:
	return _sign_in(APPLE, true)


func sign_out() -> void:
	if _requests.backend:
		_requests.backend.sign_out()


## Deletes the account. Firebase may answer "requires recent login";
## sign in again with the same provider and retry.
func delete_account() -> FirebaseTask:
	return _requests.send(&"delete_user")


func get_id_token(force_refresh := false) -> FirebaseTask:
	return _requests.send(&"get_id_token", [force_refresh])


func current_user() -> Dictionary:
	return _requests.backend.current_user() if _requests.backend else {}


func is_signed_in() -> bool:
	return not current_user().is_empty()


func _sign_in(provider: String, link: bool) -> FirebaseTask:
	if link and not is_signed_in():
		return _requests.failed(FirebaseResult.ERR_NO_USER, "link needs a signed-in user")
	return _requests.send(&"sign_in", [provider, link])
