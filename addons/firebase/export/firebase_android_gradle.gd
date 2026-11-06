@tool
extends RefCounted
## Game-owned Android build integration. The generic SDK/AAR never contains an
## app ID. Hashes protect existing game files during updates and module removal.

const Transaction := preload("res://addons/firebase/export/firebase_android_transaction.gd")
const STATE := ".godot-firebase-export.json"
const SCRIPT := "firebase-crashlytics.gradle"
const GAMES_RESOURCE := "res/values/godot_firebase_play_games.xml"
const HOOK := "\n// BEGIN GODOT FIREBASE (managed)\napply from: 'firebase-crashlytics.gradle'\n// END GODOT FIREBASE (managed)\n"
# exclusiveContent keeps the injected Gradle plugins from resolving out of any
# other repository the game's build script declares.
const CLASSPATH := """// BEGIN GODOT FIREBASE CLASSPATH (managed)
buildscript {
    repositories {
        exclusiveContent {
            forRepository { google() }
            filter { includeGroup('com.google.gms'); includeGroup('com.google.firebase') }
        }
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.google.gms:google-services:4.5.0'
        classpath 'com.google.firebase:firebase-crashlytics-gradle:3.0.8'
    }
}
// END GODOT FIREBASE CLASSPATH (managed)

"""
const TOOLCHAIN_CLASSPATH := """
    // BEGIN GODOT FIREBASE R8 (managed)
    buildscript {
        repositories {
            mavenCentral()
            exclusiveContent {
                forRepository { maven { url = uri('https://storage.googleapis.com/r8-releases/raw') } }
                filter { includeModule('com.android.tools', 'r8') }
            }
        }
        dependencies { classpath 'com.android.tools:r8:9.1.29' }
    }
    // END GODOT FIREBASE R8 (managed)
"""
const TOOLCHAIN_CONFIG := "\n// BEGIN GODOT FIREBASE KOTLIN (managed)\nversions.kotlinVersion = '2.4.0'\n// END GODOT FIREBASE KOTLIN (managed)\n"
const GOOGLE_CLASSPATH := """// BEGIN GODOT FIREBASE GOOGLE SERVICES (managed)
buildscript {
    repositories {
        exclusiveContent {
            forRepository { google() }
            filter { includeGroup('com.google.gms') }
        }
        google()
        mavenCentral()
    }
    dependencies { classpath 'com.google.gms:google-services:4.5.0' }
}
// END GODOT FIREBASE GOOGLE SERVICES (managed)

"""
## Blocks written by earlier SDK versions, upgraded in place on the next export.
const LEGACY_BLOCKS := {
	"""// BEGIN GODOT FIREBASE CLASSPATH (managed)
buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.google.gms:google-services:4.5.0'
        classpath 'com.google.firebase:firebase-crashlytics-gradle:3.0.8'
    }
}
// END GODOT FIREBASE CLASSPATH (managed)

""": CLASSPATH,
	"""
    // BEGIN GODOT FIREBASE R8 (managed)
    buildscript {
        repositories {
            mavenCentral()
            maven { url = uri('https://storage.googleapis.com/r8-releases/raw') }
        }
        dependencies { classpath 'com.android.tools:r8:9.1.29' }
    }
    // END GODOT FIREBASE R8 (managed)
""": TOOLCHAIN_CLASSPATH,
	"""// BEGIN GODOT FIREBASE GOOGLE SERVICES (managed)
buildscript {
    repositories { google(); mavenCentral() }
    dependencies { classpath 'com.google.gms:google-services:4.5.0' }
}
// END GODOT FIREBASE GOOGLE SERVICES (managed)

""": GOOGLE_CLASSPATH,
}
const OWNED_PATHS := [SCRIPT, GAMES_RESOURCE, "google-services.json"]
const DEPENDENCIES := {
	"auth": "com.google.firebase:firebase-auth:25.0.0",
	"firestore": "com.google.firebase:firebase-firestore:27.1.0",
	"storage": "com.google.firebase:firebase-storage:23.0.0",
	"database": "com.google.firebase:firebase-database:23.0.0",
	"functions": "com.google.firebase:firebase-functions:23.0.0",
	"analytics": "com.google.firebase:firebase-analytics:24.0.0",
	"crashlytics": "com.google.firebase:firebase-crashlytics-ndk:21.0.1",
	"remote_config": "com.google.firebase:firebase-config:24.0.1",
}
const METADATA := {
	"firebase/analytics_collection": "firebase_analytics_collection_enabled",
	"firebase/crashlytics_collection": "firebase_crashlytics_collection_enabled",
	"firebase/consent_analytics_storage": "google_analytics_default_allow_analytics_storage",
	"firebase/consent_ad_storage": "google_analytics_default_allow_ad_storage",
	"firebase/consent_ad_user_data": "google_analytics_default_allow_ad_user_data",
	"firebase/consent_ad_personalization": "google_analytics_default_allow_ad_personalization_signals",
}


## Gradle project directory for the gradle_build/gradle_build_directory option.
## Godot treats the option as the parent and builds in its build/ child.
static func build_directory(option: String) -> String:
	return "res://android/build" if option.is_empty() else option.path_join("build")


static func dependencies_for(modules: Array, play_games: bool) -> PackedStringArray:
	# Firebase C++ App initializes Analytics Java classes even without our API.
	var dependencies := PackedStringArray([DEPENDENCIES.analytics, "com.google.android.gms:play-services-base:18.11.1"])
	for module: String in modules:
		if DEPENDENCIES.has(module) and not dependencies.has(DEPENDENCIES[module]):
			dependencies.append(DEPENDENCIES[module])
	if modules.has("auth"):
		dependencies.append_array(PackedStringArray([
			"androidx.credentials:credentials:1.6.0",
			"androidx.credentials:credentials-play-services-auth:1.6.0",
			"com.google.android.libraries.identity.googleid:googleid:1.2.1",
		]))
		if play_games:
			dependencies.append("com.google.android.gms:play-services-games-v2:22.0.0")
	return dependencies


## 0 = SDK default (omit), 1 = enabled/granted, 2 = disabled/denied.
static func manifest_for(options: Dictionary, play_games: bool) -> String:
	var manifest := ""
	for option: String in METADATA:
		var value: int = options.get(option, 0)
		if value == 1 or value == 2:
			manifest += '<meta-data android:name="%s" android:value="%s" />\n' % [METADATA[option], "true" if value == 1 else "false"]
	if play_games:
		manifest += '<meta-data android:name="com.google.android.gms.games.APP_ID" android:value="@string/game_services_project_id" />\n'
	return manifest


## dry_run validates the same planned writes without changing game files.
static func prepare(directory: String, config: String, package_name: String, modules: Array, games_id: String, dry_run: bool = false) -> Dictionary:
	var crashlytics := modules.has("crashlytics")
	var services := crashlytics or modules.has("analytics")
	var toolchain := not modules.is_empty()
	var active := crashlytics or not games_id.is_empty() or toolchain
	var state_path := directory.path_join(STATE)
	if not active and not FileAccess.file_exists(state_path):
		return {"error": OK}
	if not games_id.is_empty() and (not games_id.is_valid_int() or games_id.begins_with("-") or games_id.begins_with("+")):
		return _failure("firebase/auth/play_games_app_id must be the numeric Play Games project ID.")
	if services:
		var parsed := FirebaseAndroidConfig.options_for(config, package_name)
		if parsed.error != OK:
			return parsed
	var build_path := directory.path_join("build.gradle")
	if not FileAccess.file_exists(build_path):
		return _failure("Install Godot's Android Gradle build template; no build.gradle at %s." % directory)
	var build := _read_managed(build_path)
	if active and not build.contains("com.android.application"):
		return _failure("Firebase supports the Godot Android app build.gradle template; this custom template has no com.android.application plugin.")
	var state: Dictionary = {}
	if FileAccess.file_exists(state_path):
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
		if not decoded is Dictionary or decoded.get("version") != 1 or not decoded.get("files") is Dictionary:
			return _failure("Invalid managed Firebase export state: %s. Restore or remove it before exporting." % state_path)
		state = decoded.files
	for path: String in state:
		if not OWNED_PATHS.has(path):
			return _failure("Unknown path in managed Firebase export state: %s." % path)
		if FileAccess.file_exists(directory.path_join(path)) and not _matches_hash(directory.path_join(path), state[path]):
			return _failure("Generated Firebase file was edited: %s. Preserve your changes and remove the managed file/state before exporting." % path)
	if not _blocks_intact(build, [HOOK, CLASSPATH, GOOGLE_CLASSPATH]) or build.contains("// BEGIN GODOT FIREBASE") and (not build.contains(HOOK) or not (build.contains(CLASSPATH) or build.contains(GOOGLE_CLASSPATH)) or not FileAccess.file_exists(state_path)):
		return _failure("The managed Firebase build.gradle block was edited or its state is missing; restore it before exporting.")
	var toolchain_config := _toolchain_config(directory, toolchain, FileAccess.file_exists(state_path))
	if toolchain_config.error != OK:
		return toolchain_config
	var toolchain_settings := _toolchain_settings(directory, toolchain, FileAccess.file_exists(state_path))
	if toolchain_settings.error != OK:
		return toolchain_settings
	var desired: Dictionary = {}
	if services:
		desired[SCRIPT] = _services_script(crashlytics)
		desired["google-services.json"] = config
	if not games_id.is_empty():
		desired[GAMES_RESOURCE] = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="game_services_project_id" translatable="false">%s</string>\n</resources>\n' % games_id
	var next_state: Dictionary = {}
	for path: String in desired:
		if FileAccess.file_exists(directory.path_join(path)) and not state.has(path):
			if path == "google-services.json" and _read_lf(directory.path_join(path)) == _lf(desired[path]):
				continue # A matching pre-existing game config remains game-owned.
			return _failure("Firebase export would overwrite game-owned %s. Move it aside or use a matching game configuration." % path)
		next_state[path] = _lf(desired[path]).sha256_text()
	var next_build := build.replace(HOOK, "").replace(CLASSPATH, "").replace(GOOGLE_CLASSPATH, "")
	if crashlytics:
		next_build = CLASSPATH + next_build + HOOK
	elif services:
		next_build = GOOGLE_CLASSPATH + next_build + HOOK
	if dry_run:
		return {"error": OK}
	var changes := {}
	for path: String in state:
		if not desired.has(path) and FileAccess.file_exists(directory.path_join(path)):
			changes[directory.path_join(path)] = null
	for path: String in next_state:
		_queue_text(changes, directory.path_join(path), desired[path])
	_queue_text(changes, build_path, next_build)
	if toolchain_config.has("content"):
		_queue_text(changes, directory.path_join("config.gradle"), toolchain_config.content)
	if toolchain_settings.has("content"):
		_queue_text(changes, directory.path_join("settings.gradle"), toolchain_settings.content)
	if active:
		_queue_text(changes, state_path, JSON.stringify({"version": 1, "files": next_state}, "\t") + "\n")
	else:
		changes[state_path] = null
	return Transaction.apply(changes, directory)


## A committed android/build may be checked out with CRLF (Windows core.autocrlf).
## Managed blocks and hashes compare LF text, so every host sees the same files.
static func _lf(text: String) -> String:
	return text.replace("\r\n", "\n")


static func _read_lf(path: String) -> String:
	return _lf(FileAccess.get_file_as_string(path))


## LF text of a game Gradle file with earlier managed blocks upgraded.
static func _read_managed(path: String) -> String:
	var text := _read_lf(path)
	for legacy: String in LEGACY_BLOCKS:
		text = text.replace(legacy, LEGACY_BLOCKS[legacy])
	return text


## Each managed block appears at most once, unedited, and no other managed
## marker exists, such as a second, modified copy of a block.
static func _blocks_intact(text: String, blocks: Array) -> bool:
	var intact := 0
	for block: String in blocks:
		var count := text.count(block)
		if count > 1:
			return false
		intact += count
	return text.count("// BEGIN GODOT FIREBASE") == intact and text.count("// END GODOT FIREBASE") == intact


## Hashes are of LF text; earlier versions hashed a CRLF game JSON as read.
static func _matches_hash(path: String, expected: Variant) -> bool:
	var text := FileAccess.get_file_as_string(path)
	return _lf(text).sha256_text() == expected or text.sha256_text() == expected


## Queues `text` for `path` unless the file already holds it, keeping the
## file's CRLF line endings so an export does not rewrite every line.
static func _queue_text(changes: Dictionary, path: String, text: String) -> void:
	var current := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if FileAccess.file_exists(path) and _lf(current) == _lf(text):
		return
	changes[path] = _lf(text).replace("\n", "\r\n") if current.contains("\r\n") else text


static func _toolchain_config(directory: String, enabled: bool, has_state: bool) -> Dictionary:
	var path := directory.path_join("config.gradle")
	if not FileAccess.file_exists(path):
		return _failure("Firebase requires Godot's standard Android config.gradle for the pinned Kotlin/R8 toolchain.") if enabled else {"error": OK}
	var original := _read_lf(path)
	if not _blocks_intact(original, [TOOLCHAIN_CONFIG]) or (original.contains(TOOLCHAIN_CONFIG) and not has_state):
		return _failure("The managed Firebase Kotlin block was edited or its state is missing; restore it before exporting.")
	var next := original.replace(TOOLCHAIN_CONFIG, "")
	if enabled:
		var version := RegEx.create_from_string("kotlinVersion\\s*:\\s*['\"]([0-9]+)\\.([0-9]+)\\.([0-9]+)['\"]").search(next)
		if version == null or next.count("kotlinVersion") != 1:
			return _failure("Unsupported Android config.gradle: expected one literal kotlinVersion in Godot's versions map.")
		var major := version.get_string(1).to_int()
		var minor := version.get_string(2).to_int()
		if major > 2 or (major == 2 and minor > 4):
			return _failure("This custom Kotlin version needs a matching R8 toolchain; the SDK's verified Kotlin line is 2.4.x.")
		if major < 2 or minor < 4:
			next += TOOLCHAIN_CONFIG
	return {"error": OK, "content": next} if next != original else {"error": OK}


static func _toolchain_settings(directory: String, enabled: bool, has_state: bool) -> Dictionary:
	var path := directory.path_join("settings.gradle")
	if not FileAccess.file_exists(path):
		return _failure("Firebase requires Godot's standard Android settings.gradle for its pinned R8 toolchain.") if enabled else {"error": OK}
	var original := _read_lf(path)
	var upgraded := _read_managed(path)
	if not _blocks_intact(upgraded, [TOOLCHAIN_CLASSPATH]) or (upgraded.contains(TOOLCHAIN_CLASSPATH) and not has_state):
		return _failure("The managed Firebase R8 block was edited or its state is missing; restore it before exporting.")
	var next := upgraded.replace(TOOLCHAIN_CLASSPATH, "")
	if enabled:
		var matches := RegEx.create_from_string("(?m)^pluginManagement\\s*\\{").search_all(next)
		if matches.size() != 1 or not next.contains("version versions.kotlinVersion"):
			return _failure("Unsupported Android settings.gradle: Firebase expects Godot's standard pluginManagement using versions.kotlinVersion.")
		next = next.insert(matches[0].get_end(), TOOLCHAIN_CLASSPATH)
	return {"error": OK, "content": next} if next != original else {"error": OK}


static func _failure(message: String) -> Dictionary:
	return {"error": ERR_INVALID_DATA, "message": message}


static func _services_script(crashlytics: bool) -> String:
	var script := "// Generated by Godot Firebase. This file belongs to this game's Gradle build.\napply plugin: 'com.google.gms.google-services'\n"
	if not crashlytics:
		return script
	return script + """apply plugin: 'com.google.firebase.crashlytics'

def uploadRequested = project.findProperty('firebaseCrashlyticsUploadEnabled') == 'true'
def nativeSymbols = project.findProperty('firebaseCrashlyticsUnstrippedNativeLibsDir')
android.buildTypes.configureEach {
    firebaseCrashlytics {
        // Keep a real mapping/build ID even for builds that never upload.
        // Disabling this setting would embed the SDK's all-zero placeholder.
        mappingFileUploadEnabled = true
        nativeSymbolUploadEnabled = uploadRequested && nativeSymbols != null
        if (nativeSymbols != null) {
            unstrippedNativeLibsDir = project.file(nativeSymbols)
        }
    }
}
// Normal builds preserve mappings and native inputs but cannot send them.
tasks.configureEach {
    if (name.startsWith('uploadCrashlytics')) {
        enabled = uploadRequested
    }
}
"""
