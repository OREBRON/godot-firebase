extends FirebaseTest

const Plugin := preload("res://addons/firebase/export/firebase_ios_export_plugin.gd")

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

	var present := "res://tests/fixtures/google-services.json"
	var missing := "res://tests/fixtures/missing/GoogleService-Info.plist"
	var config: Dictionary = Plugin.export_configuration({"firebase/consent_ad_storage": 2}, "", "123-test.apps.googleusercontent.com", present)
	check(config.error == OK and config.content.contains("ALLOW_AD_STORAGE</key><false/>") and config.content.contains("GIDClientID"), "valid export adds startup and Google plist content")
	check(Plugin.export_configuration({}, "", null, missing).error != OK, "missing GoogleService-Info.plist fails the export")
	check(Plugin.export_configuration({"firebase/consent_ad_storage": 2}, "<key>GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE</key><true/>", null, present).error != OK, "conflicting denied consent fails the export instead of being dropped")
	check(Plugin.export_configuration({}, "", "", present).error != OK, "Google sign-in without a client ID fails the export")
	check(Plugin.FAIL_BUILD_CODE.begins_with("#error \"") and Plugin.FAIL_BUILD_CODE.count("\"") == 2, "failure code is a single fixed #error directive")
