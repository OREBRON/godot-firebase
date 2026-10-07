@tool
extends RefCounted
## AdMob App ID rule shared by the Android and iOS exports. The ID belongs to the
## game; the Mobile Ads SDK reads it at startup and crashes the app without it.

const APP_ID_OPTION := "firebase/admob_app_id"
# \z instead of $: PCRE's $ also matches before a trailing newline.
const APP_ID_PATTERN := "^ca-app-pub-[0-9]{16}~[0-9]{10}\\z"


## Empty when `app_id` is an AdMob App ID; otherwise the export error to report.
static func app_id_error(app_id: String) -> String:
	if app_id.is_empty():
		return "AdMob is selected: set %s to this game's AdMob App ID; the app crashes at startup without it." % APP_ID_OPTION
	if RegEx.create_from_string(APP_ID_PATTERN).search(app_id) == null:
		return "%s must be the AdMob App ID (ca-app-pub-<16 digits>~<10 digits>), not an ad unit ID with '/'." % APP_ID_OPTION
	return ""
