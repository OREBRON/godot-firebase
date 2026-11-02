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
const PLAY_GAMES := "play_games"
const GOOGLE := "google"
const PLAY_GAMES_PLATFORM := "play_games_platform"

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


## Opens the platform Google account picker. Requires configured OAuth client IDs.
func sign_in_with_google() -> FirebaseTask:
	return _sign_in(GOOGLE, false)


func link_with_google() -> FirebaseTask:
	return _sign_in(GOOGLE, true)


## Android Play Games v2: obtains a fresh server code using the configured web client ID.
func sign_in_with_play_games_platform() -> FirebaseTask:
	return _sign_in(PLAY_GAMES_PLATFORM, false)


func link_with_play_games_platform() -> FirebaseTask:
	return _sign_in(PLAY_GAMES_PLATFORM, true)


## Pass a fresh single-use server auth code from Play Games Services v2.
func sign_in_with_play_games(server_auth_code: String) -> FirebaseTask:
	return _sign_in(PLAY_GAMES, false, server_auth_code)


## Keeps the current (usually anonymous) uid and its data.
func link_with_game_center() -> FirebaseTask:
	return _sign_in(GAME_CENTER, true)


func link_with_apple() -> FirebaseTask:
	return _sign_in(APPLE, true)


func link_with_play_games(server_auth_code: String) -> FirebaseTask:
	return _sign_in(PLAY_GAMES, true, server_auth_code)


func sign_out() -> void:
	if _requests.backend:
		_requests.backend.sign_out()


## Deletes the account. Firebase may answer "requires recent login";
## sign in again with the same provider and retry.
func delete_account() -> FirebaseTask:
	return _requests.send(&"delete_user")


## App Store 5.1.1(v): call before deleting an account. On an account with an
## apple.com provider, shows Sign in with Apple once more and revokes its Apple
## tokens (iOS only); the value is true. Other accounts get false and no UI.
func revoke_apple_token() -> FirebaseTask:
	return _requests.send(&"revoke_apple_token")


func get_id_token(force_refresh := false) -> FirebaseTask:
	return _requests.send(&"get_id_token", [force_refresh])


func current_user() -> Dictionary:
	return _requests.backend.current_user() if _requests.backend else {}


func is_signed_in() -> bool:
	return not current_user().is_empty()


func _sign_in(provider: String, link: bool, server_auth_code := "") -> FirebaseTask:
	if link and not is_signed_in():
		return _requests.failed(FirebaseResult.ERR_NO_USER, "link needs a signed-in user")
	if provider == PLAY_GAMES:
		if server_auth_code.is_empty():
			return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "Play Games server auth code is required")
		return _requests.send(&"sign_in_play_games", [server_auth_code, link])
	return _requests.send(&"sign_in", [provider, link])
