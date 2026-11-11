class_name FirebaseAuth
extends RefCounted
## Firebase Authentication API.
##
## Users are dictionaries: {uid, email, display_name, photo_url, is_anonymous,
## providers}. `providers` lists Firebase provider IDs such as "google.com",
## "apple.com", "gc.apple.com", "playgames.google.com" and "password".
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


## Pass a token minted by the game's server with the Firebase Admin SDK.
func sign_in_with_custom_token(token: String) -> FirebaseTask:
	return _send(&"sign_in_with_custom_token", [token], "custom token is required" if token.is_empty() else "")


## Signs in to an existing email/password account.
func sign_in_with_email(email: String, password: String) -> FirebaseTask:
	return _send(&"sign_in_with_email", [email, password], validate_email(email, password))


## Proves again that the player owns the signed-in account, for example before
## delete_account(). Fails when the credential belongs to another account.
func reauthenticate_with_google() -> FirebaseTask:
	return _reauthenticate(&"reauthenticate", [GOOGLE])


func reauthenticate_with_apple() -> FirebaseTask:
	return _reauthenticate(&"reauthenticate", [APPLE])


func reauthenticate_with_game_center() -> FirebaseTask:
	return _reauthenticate(&"reauthenticate", [GAME_CENTER])


func reauthenticate_with_play_games_platform() -> FirebaseTask:
	return _reauthenticate(&"reauthenticate", [PLAY_GAMES_PLATFORM])


func reauthenticate_with_email(email: String, password: String) -> FirebaseTask:
	return _reauthenticate(&"reauthenticate_with_email", [email, password], validate_email(email, password))


## Pass a Firebase provider ID from current_user().providers, e.g. "google.com".
## Read current_user() afterwards for the remaining providers.
func unlink_provider(provider_id: String) -> FirebaseTask:
	return _send(&"unlink_provider", [provider_id], "provider ID is required" if provider_id.is_empty() else "")


## Keys: display_name and photo_url (Strings). A key left out keeps its value;
## "" clears it. Read current_user() afterwards; state_changed is not emitted.
func update_profile(profile: Dictionary) -> FirebaseTask:
	return _send(&"update_profile", [profile], validate_profile(profile))


## Fetches the account again, e.g. after it changed on another device or the
## server. Read current_user() afterwards.
func reload_user() -> FirebaseTask:
	return _requests.send(&"reload_user")


func sign_out() -> void:
	if _requests.backend:
		_requests.backend.sign_out()


## Deletes the account. Firebase may answer "requires recent login"
## (error_code 9): reauthenticate with one of the account's providers and retry.
## Custom token and Play Games server-code accounts sign in again with a fresh
## token or code instead.
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


static func validate_email(email: String, password: String) -> String:
	return "email and password are required" if email.is_empty() or password.is_empty() else ""


static func validate_profile(profile: Dictionary) -> String:
	for key: Variant in profile:
		if not key is String or key not in ["display_name", "photo_url"] or not profile[key] is String:
			return "profile keys are display_name and photo_url with String values"
	return ""


func _send(method: StringName, args: Array, reason: String) -> FirebaseTask:
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _requests.send(method, args)


func _reauthenticate(method: StringName, args: Array, reason := "") -> FirebaseTask:
	if not is_signed_in():
		return _requests.failed(FirebaseResult.ERR_NO_USER, "reauthentication needs a signed-in user")
	return _send(method, args, reason)


func _sign_in(provider: String, link: bool, server_auth_code := "") -> FirebaseTask:
	if link and not is_signed_in():
		return _requests.failed(FirebaseResult.ERR_NO_USER, "link needs a signed-in user")
	if provider == PLAY_GAMES:
		if server_auth_code.is_empty():
			return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "Play Games server auth code is required")
		return _requests.send(&"sign_in_play_games", [server_auth_code, link])
	return _requests.send(&"sign_in", [provider, link])
