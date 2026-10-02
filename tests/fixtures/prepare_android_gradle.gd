extends SceneTree
## Used by tools/test_android_export.py; never contacts Firebase.
const Gradle := preload("res://addons/firebase/export/firebase_android_gradle.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		push_error("Expected Gradle directory, input JSON, Android package, module list and Play Games ID")
		quit(2)
		return
	var modules := Array(args[3].split(",", false))
	var result := Gradle.prepare(args[0], FileAccess.get_file_as_string(args[1]), args[2], modules, args[4])
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	var file := FileAccess.open(args[0].path_join("src/main/AndroidManifest.xml"), FileAccess.WRITE)
	file.store_string('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application>' + Gradle.manifest_for({
		"firebase/analytics_collection": 2, "firebase/crashlytics_collection": 2,
		"firebase/consent_analytics_storage": 2, "firebase/consent_ad_storage": 2,
		"firebase/consent_ad_user_data": 2, "firebase/consent_ad_personalization": 2,
	}, not args[4].is_empty()) + '</application></manifest>')
	file.close()
	file = FileAccess.open(args[0].path_join("build.gradle"), FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("\ndependencies {\n")
	for dependency in Gradle.dependencies_for(modules, not args[4].is_empty()):
		file.store_string("    implementation '%s'\n" % dependency)
	file.store_string("}\n")
	file.close()
	quit(0)
