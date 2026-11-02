extends FirebaseTest

const HELPER := "res://addons/firebase/export/firebase_android_gradle.gd"
const PACKAGE := "org.godotengine.firebase.test"
var _helper: GDScript
var _directory := ""


func _run() -> void:
	if Engine.is_editor_hint():
		await create_timer(1.0).timeout # Let the editor finish its startup scan.
	check(FileAccess.file_exists(HELPER), "Android export prepares the game's Gradle integration")
	if not FileAccess.file_exists(HELPER):
		return
	_helper = load(HELPER)
	_check_exporter()
	_check_build_directory()
	_check_dependencies()
	_check_startup_options()
	_directory = "user://android-export-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_directory)
	_check_preparation()
	_check_toolchain()
	_check_analytics_only()
	_check_crlf_checkout()
	_remove_tree(_directory)


func _check_exporter() -> void:
	if not Engine.is_editor_hint():
		return # EditorExportPlugin can only instantiate in --editor runs.
	var exporter: EditorExportPlugin = load("res://addons/firebase/export/firebase_android_export_plugin.gd").new()
	check(exporter.has_method("_get_export_options_overrides"), "Firebase forces Gradle for required AAR/Maven integration")
	if exporter.has_method("_get_export_options_overrides"):
		check(exporter._get_export_options_overrides(null).get("gradle_build/use_gradle_build") == true, "prebuilt export cannot silently omit Firebase dependencies")
	for option in exporter._get_export_options(null):
		if option.option.name != "firebase/google_services_json":
			check(option.default_value == 0, "collection/consent export defaults preserve SDK behavior")
	exporter._export_error = "Fixture configuration failure"
	check(exporter._get_android_manifest_application_element_contents(null, false).contains("godot_firebase_configuration_error_see_export_log"), "a preparation error forces resource compilation to fail")


## Godot 4.7 ExportTemplateManager::get_android_build_directory().
func _check_build_directory() -> void:
	check(_helper.build_directory("") == "res://android/build", "default Gradle build directory matches Godot")
	check(_helper.build_directory("res://platform/android") == "res://platform/android/build", "custom gradle_build_directory is the parent of Godot's Gradle project")


func _check_dependencies() -> void:
	var minimal: PackedStringArray = _helper.dependencies_for([], false)
	check(minimal.has("com.google.firebase:firebase-analytics:24.0.0"), "Firebase C++ App keeps its Analytics Java dependency")
	check(not str(minimal).contains("games-v2"), "Play Games is absent by default")
	var auth: PackedStringArray = _helper.dependencies_for(["auth"], false)
	check(auth.has("androidx.credentials:credentials:1.6.0"), "Google login includes Credential Manager")
	check(auth.has("androidx.credentials:credentials-play-services-auth:1.6.0"), "Google login includes the Play Services credential provider")
	check(auth.has("com.google.android.libraries.identity.googleid:googleid:1.2.1"), "Google login includes Google ID")
	check(not str(auth).contains("games-v2"), "Auth does not enable Play Games implicitly")
	check(str(_helper.dependencies_for(["auth"], true)).contains("games-v2:22.0.0"), "Play Games is explicitly selectable")
	check(not str(_helper.dependencies_for(["firestore"], true)).contains("games-v2"), "Play Games requires the Auth module")
	var products: PackedStringArray = _helper.dependencies_for(["analytics", "crashlytics", "remote_config"], false)
	check(products.count("com.google.firebase:firebase-analytics:24.0.0") == 1, "Analytics dependency is deduplicated")
	check(products.has("com.google.firebase:firebase-config:24.0.1"), "Remote Config Java dependency is included")
	check(products.has("com.google.firebase:firebase-crashlytics-ndk:21.0.1"), "Crashlytics includes NDK support")


func _check_startup_options() -> void:
	check(_helper.manifest_for({}, false).is_empty(), "SDK defaults omit collection and consent metadata")
	var options := {"firebase/analytics_collection": 2, "firebase/crashlytics_collection": 1,
		"firebase/consent_analytics_storage": 2, "firebase/consent_ad_storage": 1,
		"firebase/consent_ad_user_data": 2, "firebase/consent_ad_personalization": 1}
	var manifest: String = _helper.manifest_for(options, true)
	for pair in [["firebase_analytics_collection_enabled", false], ["firebase_crashlytics_collection_enabled", true],
		["google_analytics_default_allow_analytics_storage", false], ["google_analytics_default_allow_ad_storage", true],
		["google_analytics_default_allow_ad_user_data", false], ["google_analytics_default_allow_ad_personalization_signals", true]]:
		check(manifest.contains('android:name="%s" android:value="%s"' % pair), "startup metadata: %s" % pair[0])
	check(manifest.contains('android:value="@string/game_services_project_id"'), "Play Games APP_ID refers to a string resource")
	check(not _helper.manifest_for({}, false).contains("games.APP_ID"), "disabled Play Games has no APP_ID metadata")


func _check_preparation() -> void:
	var build := "plugins { id 'com.android.application' }\nandroid { }\n// Game-owned customization\n"
	_write("build.gradle", build)
	_write("config.gradle", "ext.versions = [kotlinVersion: '2.1.21', androidGradlePlugin: '8.6.1']\n")
	_write("settings.gradle", "pluginManagement { apply from: 'config.gradle'; plugins { id 'org.jetbrains.kotlin.android' version versions.kotlinVersion } }\n")
	var config := FileAccess.get_file_as_string("res://tests/fixtures/google-services.json")
	var result: Dictionary = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "123456789", true)
	check(result.error == OK and _read("build.gradle") == build and not FileAccess.file_exists(_directory.path_join("google-services.json")), "export warnings validate without changing game files")
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "123456789")
	check(result.error == OK, "Crashlytics and Play Games preparation succeeds: %s" % result)
	check(_read("google-services.json") == config, "game JSON is staged in the Gradle app module")
	check(_read("res/values/godot_firebase_play_games.xml").contains('name="game_services_project_id"'), "PGS string resource is generated")
	var prepared := _read("build.gradle")
	check(prepared.contains("Game-owned customization"), "game Gradle customization is preserved")
	check(prepared.count("apply from: 'firebase-crashlytics.gradle'") == 1, "exactly one managed Gradle hook is inserted")
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "123456789")
	check(result.error == OK and _read("build.gradle") == prepared, "repeated preparation is idempotent")
	var script := _read("firebase-crashlytics.gradle")
	_write("firebase-crashlytics.gradle", script + "// game customization\n")
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "123456789")
	check(result.error != OK and _read("firebase-crashlytics.gradle").ends_with("// game customization\n"), "edited generated files are preserved with a configuration error")
	_write("firebase-crashlytics.gradle", script)
	var second := config.replace("0123456789abcdef", "fedcba9876543210")
	result = _helper.prepare(_directory, second, PACKAGE, ["crashlytics"], "")
	check(result.error == OK and _read("google-services.json") == second, "another game config replaces only the generated JSON")
	check(not FileAccess.file_exists(_directory.path_join("res/values/godot_firebase_play_games.xml")), "disabling Play Games removes its generated resource")
	result = _helper.prepare(_directory, "", PACKAGE, [], "")
	check(result.error == OK, "module removal cleans up managed integration")
	check(_read("build.gradle") == build, "cleanup restores the original Gradle file exactly")
	for file in ["google-services.json", "firebase-crashlytics.gradle", ".godot-firebase-export.json"]:
		check(not FileAccess.file_exists(_directory.path_join(file)), "cleanup removes generated %s" % file)
	_write("google-services.json", "game-owned conflicting config")
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "")
	check(result.error != OK, "conflicting game-owned JSON is rejected")
	check(_read("google-services.json") == "game-owned conflicting config" and _read("build.gradle") == build, "conflict leaves game files unchanged")
	_write("google-services.json", config)
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "")
	check(result.error == OK, "matching game-owned JSON can be used")
	result = _helper.prepare(_directory, "", PACKAGE, [], "")
	check(result.error == OK and _read("google-services.json") == config, "cleanup preserves pre-existing game-owned JSON")
	result = _helper.prepare(_directory, config, "wrong.package", ["crashlytics"], "")
	check(result.error != OK and _read("build.gradle") == build, "wrong Firebase package fails before mutations")
	for invalid_id in ["123'; malicious", " 123", "123\n", "+123", "-123", "1.2"]:
		result = _helper.prepare(_directory, config, PACKAGE, [], invalid_id)
		check(result.error != OK, "Play Games application ID must contain only digits: %s" % invalid_id)
	_write("build.gradle", "// Unsupported custom template\n")
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "")
	check(result.error != OK, "unsupported template fails clearly before producing a broken Crashlytics app")


func _check_toolchain() -> void:
	check("TOOLCHAIN_CONFIG" in _helper.get_script_constant_map(), "export upgrades the Kotlin/R8 toolchain for pinned Firebase dependencies")
	if not "TOOLCHAIN_CONFIG" in _helper.get_script_constant_map():
		return
	var build := "plugins { id 'com.android.application'; id 'org.jetbrains.kotlin.android' }\n"
	var config := "ext.versions = [kotlinVersion: '2.1.21', androidGradlePlugin: '8.6.1']\n"
	var settings := "pluginManagement { apply from: 'config.gradle'; plugins { id 'org.jetbrains.kotlin.android' version versions.kotlinVersion } }\n"
	_write("build.gradle", build)
	_write("config.gradle", config)
	_write("settings.gradle", settings)
	var result: Dictionary = _helper.prepare(_directory, "", PACKAGE, ["auth"], "")
	check(result.error == OK, "standard Godot toolchain is prepared")
	check(_read("config.gradle").contains("versions.kotlinVersion = '2.4.0'"), "compiler supports Google ID Kotlin 2.4 metadata")
	check(_read("settings.gradle").contains("com.android.tools:r8:9.1.29"), "R8 supports the selected Kotlin metadata before AGP loads")
	check(not _read("build.gradle").contains("firebase-crashlytics-gradle"), "toolchain-only preparation does not apply Crashlytics")
	result = _helper.prepare(_directory, "", PACKAGE, ["auth"], "")
	check(result.error == OK and _read("config.gradle").count("versions.kotlinVersion = '2.4.0'") == 1, "toolchain preparation is idempotent")
	result = _helper.prepare(_directory, "", PACKAGE, [], "")
	check(result.error == OK and _read("config.gradle") == config and _read("build.gradle") == build and _read("settings.gradle") == settings, "removal restores the original toolchain configuration byte for byte")
	_write("settings.gradle", "// custom plugin resolution\n")
	result = _helper.prepare(_directory, "", PACKAGE, ["auth"], "")
	check(result.error != OK and _read("config.gradle") == config and _read("build.gradle") == build, "unsupported custom plugin resolution fails without mutations")


func _check_analytics_only() -> void:
	_write("settings.gradle", "pluginManagement { apply from: 'config.gradle'; plugins { id 'org.jetbrains.kotlin.android' version versions.kotlinVersion } }\n")
	var config := FileAccess.get_file_as_string("res://tests/fixtures/google-services.json")
	var result: Dictionary = _helper.prepare(_directory, config, PACKAGE, ["analytics"], "")
	check(result.error == OK, "Analytics-only preparation succeeds")
	check(_read("build.gradle").contains("com.google.gms:google-services:4.5.0"), "Analytics gets startup Google Services resources")
	check(not _read("build.gradle").contains("firebase-crashlytics-gradle"), "Analytics does not add the Crashlytics plugin dependency")
	var script := _read("firebase-crashlytics.gradle")
	check(script.contains("com.google.gms.google-services") and not script.contains("com.google.firebase.crashlytics"), "Analytics applies only Google Services")
	result = _helper.prepare(_directory, "", PACKAGE, [], "")
	check(result.error == OK, "Analytics-only integration is removed cleanly")


## Windows core.autocrlf checks a committed android/build out with CRLF line endings.
func _check_crlf_checkout() -> void:
	var build := "plugins { id 'com.android.application' }\r\nandroid { }\r\n// Game-owned customization\r\n"
	var config_gradle := "ext.versions = [kotlinVersion: '2.1.21', androidGradlePlugin: '8.6.1']\r\n"
	var settings := "pluginManagement { apply from: 'config.gradle'; plugins { id 'org.jetbrains.kotlin.android' version versions.kotlinVersion } }\r\n"
	_write("build.gradle", build)
	_write("config.gradle", config_gradle)
	_write("settings.gradle", settings)
	var config := FileAccess.get_file_as_string("res://tests/fixtures/google-services.json")
	var result: Dictionary = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "123456789")
	check(result.error == OK, "CRLF Gradle templates are prepared: %s" % result)
	for file in ["build.gradle", "config.gradle", "settings.gradle"]:
		check(not _read(file).replace("\r\n", "").contains("\n"), "managed blocks keep the CRLF style of %s" % file)
	var prepared := {}
	for file in ["build.gradle", "config.gradle", "settings.gradle", "firebase-crashlytics.gradle", "google-services.json", "res/values/godot_firebase_play_games.xml", ".godot-firebase-export.json"]:
		_write(file, _read(file).replace("\r\n", "\n").replace("\n", "\r\n"))
		prepared[file] = _read(file)
	result = _helper.prepare(_directory, config, PACKAGE, ["crashlytics"], "123456789")
	check(result.error == OK, "a CRLF checkout of prepared files exports again: %s" % result)
	check(prepared.keys().all(func(file): return _read(file) == prepared[file]), "repeated CRLF preparation changes nothing")
	result = _helper.prepare(_directory, "", PACKAGE, [], "")
	check(result.error == OK and _read("build.gradle") == build and _read("config.gradle") == config_gradle and _read("settings.gradle") == settings, "CRLF removal restores the original files byte for byte")

	# Earlier versions stored the hash of a CRLF game JSON as read.
	var crlf_config := config.replace("\n", "\r\n")
	result = _helper.prepare(_directory, crlf_config, PACKAGE, ["crashlytics"], "")
	var state: Dictionary = JSON.parse_string(_read(".godot-firebase-export.json"))
	state.files["google-services.json"] = crlf_config.sha256_text()
	_write(".godot-firebase-export.json", JSON.stringify(state, "\t") + "\n")
	result = _helper.prepare(_directory, crlf_config, PACKAGE, ["crashlytics"], "")
	check(result.error == OK, "state written by earlier versions for a CRLF game JSON stays valid: %s" % result)
	result = _helper.prepare(_directory, "", PACKAGE, [], "")
	check(result.error == OK and not FileAccess.file_exists(_directory.path_join("google-services.json")), "CRLF game JSON integration is removed cleanly")


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(_directory.path_join(path), FileAccess.WRITE)
	file.store_string(content)


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(_directory.path_join(path))


func _remove_tree(path: String) -> void:
	for child in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	for child in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
