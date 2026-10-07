extends FirebaseTest

const Plugin := preload("res://addons/firebase/export/firebase_ios_export_plugin.gd")
const APP_ID := "ca-app-pub-3940256099942544~1458002511"
const GOOGLE_NETWORK := "cstr6suwn9.skadnetwork"

func _run() -> void:
	check(Plugin.startup_plist({}).is_empty(), "absent startup choices preserve SDK defaults")
	var plist: String = Plugin.startup_plist({"firebase/analytics_collection": 2, "firebase/crashlytics_collection": 1, "firebase/consent_ad_user_data": 2})
	check(plist.contains("<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key><false/>"), "Analytics disabled before initialization")
	check(plist.contains("<key>FirebaseCrashlyticsCollectionEnabled</key><true/>"), "Crashlytics startup enabled")
	check(plist.contains("<key>GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA</key><false/>"), "consent startup denied")
	check(not plist.contains("AD_STORAGE"), "omitted consent remains SDK default")
	var google: Dictionary = Plugin.google_plist("123-test.apps.googleusercontent.com", "")
	check(google.error == OK and google.content.contains("com.googleusercontent.apps.123-test"), "Google reversed client scheme exported")
	var existing := "<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>com.googleusercontent.apps.123-test</string><string>my-game</string></array></dict></array>"
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", existing)
	check(google.error == OK and not google.content.contains("CFBundleURLTypes"), "existing URL types preserved without duplicate plist key")
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", existing.replace("com.googleusercontent.apps.123-test", "other-game"))
	check(google.error != OK, "missing scheme in manually managed URL types reported")
	check(Plugin.google_plist("invalid", "").error != OK, "invalid client id rejected")

	google = Plugin.google_plist("123-test.apps.googleusercontent.com", "<key>GIDClientID</key><string>123-test.apps.googleusercontent.com</string>")
	check(google.error == OK and not google.content.contains("GIDClientID"), "matching manually configured Google client ID is not duplicated")
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", "<key>GIDClientID</key><string>other.apps.googleusercontent.com</string>")
	check(google.error != OK, "conflicting manually configured Google client ID is rejected")
	var unrelated_scheme := existing.replace("com.googleusercontent.apps.123-test", "other-game") + "<key>OtherSetting</key><string>com.googleusercontent.apps.123-test</string>"
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", unrelated_scheme)
	check(google.error != OK, "scheme in unrelated setting does not satisfy provider callback requirement")
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", "<!-- <key>CFBundleURLTypes</key><string>com.googleusercontent.apps.123-test</string> -->")
	check(google.error == OK and google.content.contains("CFBundleURLTypes"), "commented URL types do not suppress provider callback generation")

	var matching_startup := "<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key><false/>"
	var startup: Dictionary = Plugin.startup_plist_checked({"firebase/analytics_collection": 2, "firebase/crashlytics_collection": 1}, matching_startup)
	check(startup.error == OK and not startup.content.contains("FIREBASE_ANALYTICS_COLLECTION_ENABLED"), "matching manual startup preference is not duplicated")
	check(startup.error == OK and startup.content.contains("FirebaseCrashlyticsCollectionEnabled"), "other startup preferences are still emitted")
	startup = Plugin.startup_plist_checked({"firebase/analytics_collection": 1}, matching_startup)
	check(startup.error != OK, "conflicting manual startup preference is rejected")
	startup = Plugin.startup_plist_checked({"firebase/analytics_collection": 2}, matching_startup.replace("<false/>", "<string>false</string>"))
	check(startup.error != OK, "startup preference requires an actual plist boolean")
	startup = Plugin.startup_plist_checked({}, matching_startup)
	check(startup.error == OK and startup.content.is_empty(), "SDK-default export choice preserves manually managed preference")
	startup = Plugin.startup_plist_checked({"firebase/analytics_collection": 2}, matching_startup + matching_startup)
	check(startup.error != OK, "duplicate manually managed plist keys are rejected")

	var formatted := "<key >CFBundleURLTypes</key >\n<array><dict><!-- provider -->\n<key>CFBundleURLSchemes</key><array><string>com.googleusercontent.apps.123-test</string></array></dict></array>"
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", formatted)
	check(google.error == OK and not google.content.contains("CFBundleURLTypes"), "XML tag whitespace and comments preserve actual callback array")
	var nested_client := "<key>OtherSetting</key><dict><key>GIDClientID</key><string>other.apps.googleusercontent.com</string></dict>"
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", nested_client)
	check(google.error == OK and google.content.contains("GIDClientID"), "nested client ID cannot impersonate top-level Google configuration")
	var wrong_array := "<key>CFBundleURLTypes</key><array><dict><key>OtherSchemes</key><array><string>com.googleusercontent.apps.123-test</string></array></dict></array>"
	check(Plugin.google_plist("123-test.apps.googleusercontent.com", wrong_array).error != OK, "nested unrelated array cannot impersonate callback schemes")
	google = Plugin.google_plist("123-test.apps.googleusercontent.com", "<key>GIDClientID</key><string>123&#45;test.apps.googleusercontent.com</string>")
	check(google.error == OK and not google.content.contains("GIDClientID"), "XML entity in existing matching client ID is decoded")
	for malformed in ["<key>GIDClientID</key>", "<key>GIDClientID</key><string>client</array>", "<key>CFBundleURLTypes</key><array/>", "<key>GIDClientID</key><integer>123</integer>"]:
		check(Plugin.google_plist("123-test.apps.googleusercontent.com", malformed).error != OK, "invalid Google plist structure is rejected: " + malformed)
	for option in Plugin.STARTUP_KEYS:
		var key: String = Plugin.STARTUP_KEYS[option]
		startup = Plugin.startup_plist_checked({option: 2}, "<key>%s</key><true/>" % key)
		check(startup.error != OK, "manual grant cannot override disabled export preference: " + option)
		startup = Plugin.startup_plist_checked({option: 2}, "<!-- <key>%s</key><true/> -->" % key)
		check(startup.error == OK and startup.content.contains("<false/>"), "commented startup preference does not override explicit choice: " + option)

	google = Plugin.google_plist("123-test.apps.googleusercontent.com", "<key>GIDClientID</key><string><![CDATA[123-test.apps.googleusercontent.com]]></string>")
	check(google.error == OK and not google.content.contains("GIDClientID"), "CDATA preserves matching client ID without parser errors")
	_check_admob()
	await _check_admob_options()


func _check_admob() -> void:
	var admob: Dictionary = Plugin.admob_plist(["auth"], "", "Ads", "<key>GADApplicationIdentifier</key><string>other</string>")
	check(admob.error == OK and admob.content.is_empty(), "without AdMob its options and plist keys are ignored")
	admob = Plugin.admob_plist(["admob"], APP_ID, "", "")
	check(admob.error == OK, "AdMob plist is generated: %s" % admob)
	var values := _values(admob.get("content", ""))
	check(_string(values, "GADApplicationIdentifier") == APP_ID, "AdMob App ID is exported as GADApplicationIdentifier")
	check(_identifiers(values) == [GOOGLE_NETWORK], "Google's SKAdNetwork identifier is exported")
	check(not values.has("NSUserTrackingUsageDescription"), "no tracking description unless the game sets one")
	for invalid in ["", "ca-app-pub-3940256099942544/1712485313", "ca-app-pub-3940256099942544~1458002511\n"]:
		admob = Plugin.admob_plist(["admob"], invalid, "", "")
		check(admob.error != OK and str(admob.get("message")).contains("firebase/admob_app_id"), "missing or malformed App ID is an export error: " + invalid.c_escape())

	var manual_id := "<key>GADApplicationIdentifier</key><string>%s</string>" % APP_ID
	admob = Plugin.admob_plist(["admob"], APP_ID, "", manual_id)
	check(admob.error == OK and not admob.content.contains("GADApplicationIdentifier"), "matching manual App ID is not duplicated")
	admob = Plugin.admob_plist(["admob"], APP_ID, "", manual_id.replace("1458002511", "0000000000"))
	check(admob.error != OK, "conflicting manual App ID is rejected")
	admob = Plugin.admob_plist(["admob"], "", "", manual_id)
	check(admob.error != OK, "the App ID option is required even when the additional plist sets it")
	admob = Plugin.admob_plist(["admob"], APP_ID, "", "<key>GADApplicationIdentifier</key><integer>1</integer>")
	check(admob.error != OK, "manual App ID must be a plist string")

	var networks := "<key>SKAdNetworkItems</key><array><dict><key>SKAdNetworkIdentifier</key><string>4fzdc2evr5.skadnetwork</string></dict>\n<!-- Google --><dict><key>SKAdNetworkIdentifier</key><string>%s</string></dict></array>" % GOOGLE_NETWORK
	admob = Plugin.admob_plist(["admob"], APP_ID, "", networks)
	check(admob.error == OK and not admob.content.contains("SKAdNetworkItems") and admob.content.contains("GADApplicationIdentifier"), "the game's SKAdNetwork list is preserved without a duplicate key")
	check(Plugin.admob_plist(["admob"], APP_ID, "", networks.replace(GOOGLE_NETWORK, "other.skadnetwork")).error != OK, "a game SKAdNetwork list without Google's identifier is rejected")
	for malformed in [
		"<key>SKAdNetworkItems</key><array/>",
		"<key>SKAdNetworkItems</key><string>%s</string>" % GOOGLE_NETWORK,
		"<key>SKAdNetworkItems</key><array><string>%s</string></array>" % GOOGLE_NETWORK,
		"<key>SKAdNetworkItems</key><array><dict><key>OtherIdentifier</key><string>%s</string></dict></array>" % GOOGLE_NETWORK,
		"<key>SKAdNetworkItems</key><array><dict><key>SKAdNetworkIdentifier</key></dict><dict><key>SKAdNetworkIdentifier</key><string>%s</string></dict></array>" % GOOGLE_NETWORK,
		"<key>SKAdNetworkItems</key><array><!-- <dict><key>SKAdNetworkIdentifier</key><string>%s</string></dict> --></array>" % GOOGLE_NETWORK,
	]:
		check(Plugin.admob_plist(["admob"], APP_ID, "", malformed).error != OK, "invalid SKAdNetworkItems is rejected: " + malformed)
	admob = Plugin.admob_plist(["admob"], APP_ID, "", "<key>OtherSetting</key><array><dict><key>SKAdNetworkIdentifier</key><string>%s</string></dict></array>" % GOOGLE_NETWORK)
	check(admob.error == OK and _identifiers(_values(admob.content)) == [GOOGLE_NETWORK], "an unrelated array cannot impersonate SKAdNetworkItems")

	var tracking := "Ads & rewards <energy>\n\"Personalized\" offers"
	admob = Plugin.admob_plist(["admob"], APP_ID, tracking, "")
	check(admob.error == OK and not admob.content.contains("<energy>"), "tracking description is XML-escaped")
	check(_string(_values(admob.get("content", "")), "NSUserTrackingUsageDescription") == tracking, "tracking description is exported when set")
	var manual_tracking := "<key>NSUserTrackingUsageDescription</key><string>Ads &amp; rewards &lt;energy&gt;\n\"Personalized\" offers</string>"
	admob = Plugin.admob_plist(["admob"], APP_ID, tracking, manual_tracking)
	check(admob.error == OK and not admob.content.contains("NSUserTrackingUsageDescription"), "matching manual tracking description is not duplicated")
	check(Plugin.admob_plist(["admob"], APP_ID, "Other text", manual_tracking).error != OK, "conflicting manual tracking description is rejected")
	admob = Plugin.admob_plist(["admob"], APP_ID, "", manual_tracking)
	check(admob.error == OK and not admob.content.contains("NSUserTrackingUsageDescription"), "an empty option leaves a manual tracking description to the game")
	check(Plugin.admob_plist(["admob"], APP_ID, "", "<key>GADApplicationIdentifier</key>").error != OK, "invalid additional plist is reported")


func _check_admob_options() -> void:
	if not Engine.is_editor_hint():
		return # EditorExportPlugin can only instantiate in --editor runs.
	await create_timer(1.0).timeout # Let the editor finish its startup scan.
	var options := {}
	for option in Plugin.new()._get_export_options(null):
		options[option.option.name] = option
	check(options.has("firebase/admob_app_id") and options["firebase/admob_app_id"].default_value == "", "the game's AdMob App ID is an export option without a default")
	var tracking: Dictionary = options.get("firebase/admob_tracking_description", {})
	check(tracking.get("default_value") == "" and tracking.get("option", {}).get("hint") == PROPERTY_HINT_MULTILINE_TEXT, "the tracking description is an optional multiline export option")


func _values(content: String) -> Dictionary:
	var parsed: Dictionary = Plugin._additional_plist_values(content)
	check(parsed.error == OK, "generated AdMob plist content is valid: %s" % parsed)
	return parsed.get("values", {})


func _string(values: Dictionary, key: String) -> Variant:
	var node: Dictionary = values.get(key, {})
	return node.text if node.get("tag") == "string" and node.children.is_empty() else null


func _identifiers(values: Dictionary) -> Array:
	var identifiers := []
	var items: Dictionary = values.get("SKAdNetworkItems", {})
	for item in items.get("children", []):
		identifiers.append(_string(Plugin._plist_dictionary(item).get("values", {}), "SKAdNetworkIdentifier"))
	return identifiers
