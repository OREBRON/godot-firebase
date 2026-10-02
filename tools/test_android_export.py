#!/usr/bin/env python3
"""Build synthetic game apps through the generated Firebase Gradle hook.

No Firebase credentials or network upload are used. Maven downloads are allowed.
Requires Android SDK, Java 17, Gradle 8.11.1 and the built generic bridge AAR.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, directory, log):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=directory, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}\n{log.read_text()[-9000:]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aar", type=Path, default=ROOT / "addons/firebase/bin/android/godot_firebase.aar")
    parser.add_argument("--gradle", default=os.environ.get("GRADLE", "gradle"))
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/android-export-verification")
    args = parser.parse_args()
    args.output = args.output.resolve()
    aar = args.aar.resolve()
    if not aar.is_file():
        parser.error(f"Build the generic Android bridge first: missing {aar}")
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        parser.error("Set ANDROID_HOME to the Android SDK")
    args.output.mkdir(parents=True, exist_ok=True)
    aar_hash = hashlib.sha256(aar.read_bytes()).hexdigest()
    evidence = []
    cases = [("game-a", "0123456789abcdef", "analytics,crashlytics,remote_config", ""),
             ("game-b", "fedcba9876543210", "auth,analytics,crashlytics,remote_config", "123456789"),
             ("auth-only", "1111111111111111", "auth", ""),
             ("remote-only", "2222222222222222", "remote_config", ""),
             ("analytics-only", "3333333333333333", "analytics", "")]
    for label, suffix, modules, games_id in cases:
        game = args.output / label
        game.mkdir(exist_ok=True)
        (game / "src/main").mkdir(parents=True, exist_ok=True)
        (game / "libs").mkdir(exist_ok=True)
        shutil.copy2(aar, game / "libs/godot_firebase.aar")
        package = "org.example." + label.replace("-", "")
        app_id = f"1:123456789:android:{suffix}"
        config = {"project_info": {"project_number": "123456789", "project_id": "sdk-export-fixture"},
                  "client": [{"client_info": {"mobilesdk_app_id": app_id,
                      "android_client_info": {"package_name": package}},
                      "api_key": [{"current_key": "synthetic-not-a-real-api-key"}]}], "configuration_version": "1"}
        source = args.output / (label + "-input.json")
        source.write_text(json.dumps(config))
        (game / "config.gradle").write_text("ext.versions = [kotlinVersion: '2.1.21', androidGradlePlugin: '8.6.1']\n")
        (game / "settings.gradle").write_text("""pluginManagement {
    apply from: 'config.gradle'
    plugins {
        id 'com.android.application' version versions.androidGradlePlugin
        id 'org.jetbrains.kotlin.android' version versions.kotlinVersion
    }
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = 'firebase-export-fixture'
""")
        (game / "local.properties").write_text("sdk.dir=" + sdk + "\n")
        (game / "gradle.properties").write_text("android.useAndroidX=true\norg.gradle.jvmargs=-Xmx2g\n")
        # Same root app-module shape and res/ source directory as Godot's template.
        (game / "src/main/kotlin").mkdir(exist_ok=True)
        (game / "src/main/kotlin/Fixture.kt").write_text("package fixture\nclass Fixture : android.app.Activity()\n")
        (game / "build.gradle").write_text(f"""plugins {{
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}}
apply from: 'config.gradle'
android {{
    namespace '{package}'
    compileSdk 36
    compileOptions {{ sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }}
    kotlinOptions {{ jvmTarget = '17' }}
    defaultConfig {{ applicationId '{package}'; minSdk 24; targetSdk 36; versionCode 1; versionName '1' }}
    sourceSets.main.res.srcDirs += ['res']
    buildTypes {{ release {{ minifyEnabled true; proguardFiles getDefaultProguardFile('proguard-android-optimize.txt') }} }}
}}
dependencies {{
    implementation files('libs/godot_firebase.aar')
}}
""")
        run([args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/fixtures/prepare_android_gradle.gd",
             "--", str(game), str(source), package, modules, games_id], ROOT, args.output / (label + "-prepare.log"))
        run([args.gradle, "--no-daemon", "--max-workers=2", "--console=plain", "assembleDebug", "assembleRelease", "--warning-mode=none"], game,
            args.output / (label + "-gradle.log"))
        values = list((game / "build/generated/res").rglob("*.xml"))
        google_values = [p for p in values if 'name="google_app_id"' in p.read_text()]
        crash_values = [p for p in values if "com.google.firebase.crashlytics.mapping_file_id" in p.read_text()]
        if "crashlytics" in modules or "analytics" in modules:
            assert google_values and any(app_id in p.read_text() for p in google_values), "wrong google_app_id"
        else:
            assert not google_values, "unselected Analytics/Crashlytics generated resources"
        if "crashlytics" in modules:
            assert crash_values, "Crashlytics build ID was not generated"
            assert all("00000000000000000000000000000000" not in p.read_text() for p in crash_values), "placeholder Crashlytics build ID"
        else:
            assert not crash_values, "unselected Crashlytics generated resources"
        assert all("firebaseCrashlyticsUploadEnabled" not in p.read_text() for p in google_values)
        log = (args.output / (label + "-gradle.log")).read_text()
        uploads = [line for line in log.splitlines() if line.startswith("> Task :uploadCrashlytics")]
        assert all(line.endswith(" SKIPPED") for line in uploads), "normal build unexpectedly executed upload"
        apk = game / "build/outputs/apk/debug/firebase-export-fixture-debug.apk"
        assert apk.is_file(), "APK missing"
        release_apk = game / "build/outputs/apk/release/firebase-export-fixture-release-unsigned.apk"
        assert release_apk.is_file(), "minified release APK missing"
        mapping = game / "build/outputs/mapping/release/mapping.txt"
        # Check the compiler that actually shrank the app, not only the declared pin.
        assert mapping.is_file(), "R8 mapping missing"
        assert "# compiler_version: 9.1.29" in mapping.read_text(), "pinned R8 override was not used"
        with zipfile.ZipFile(apk) as archive:
            assert "resources.arsc" in archive.namelist(), "APK resources missing"
        aapt = Path(sdk) / "build-tools/36.1.0/aapt2"
        manifest = subprocess.check_output([str(aapt), "dump", "xmltree", str(apk), "--file", "AndroidManifest.xml"], text=True)
        assert "firebase_analytics_collection_enabled" in manifest and "firebase_crashlytics_collection_enabled" in manifest
        assert ("com.google.android.gms.games.APP_ID" in manifest) == bool(games_id), "Play Games metadata selection mismatch"
        resources = subprocess.check_output([str(aapt), "dump", "resources", str(apk)], text=True)
        if games_id:
            assert "game_services_project_id" in resources and f'"{games_id}"' in resources, "PGS app ID was not compiled as a string"
        copied_hash = hashlib.sha256((game / "libs/godot_firebase.aar").read_bytes()).hexdigest()
        assert copied_hash == aar_hash, "generic AAR changed per game"
        evidence.append({"game": label, "modules": modules, "play_games": bool(games_id), "app_id": app_id, "aar_sha256": aar_hash,
                         "toolchain": {"agp": "8.6.1", "kotlin": "2.4.0", "r8": "9.1.29", "gradle": "8.11.1"},
                         "apk": str(apk), "google_values": [str(p) for p in google_values],
                         "crash_values": [str(p) for p in crash_values]})
    (args.output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Android export: five selections, debug + R8 release APKs, two distinct Crashlytics app IDs, Analytics-only resources, identical generic AAR; no uploads. Evidence: {args.output / 'evidence.json'}")


if __name__ == "__main__":
    main()
