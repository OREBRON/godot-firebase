#!/usr/bin/env bash
# Package the Java bridge and the C++ SDK keep rules of every module into one
# AAR that every game shares. The game's google-services.json is packed at
# export time by firebase_android_export_plugin.gd, never into this AAR.
set -euo pipefail
cd "$(dirname "$0")/.."

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ ! -f "$sdk/platforms/android-35/android.jar" ]]; then
	echo "Android AAR needs SDK platform 35 (set ANDROID_HOME)" >&2
	exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
output="${ANDROID_AAR_OUTPUT:-$PWD/addons/firebase/bin/android/godot_firebase.aar}"
mkdir -p "$stage/classes" "$stage/aar" "$(dirname "$output")"
javac --release 8 -Xlint:-options -cp "$sdk/platforms/android-35/android.jar" -d "$stage/classes" android/src/org/godotengine/godotfirebase/FirebaseBridge.java
jar --create --file "$stage/aar/classes.jar" -C "$stage/classes" .
cp android/AndroidManifest.xml "$stage/aar/AndroidManifest.xml"
touch "$stage/aar/R.txt"
printf '%s\n' '-keep class org.godotengine.godotfirebase.FirebaseBridge { *; }' > "$stage/aar/proguard.txt"
for module in app auth firestore storage database functions; do
	pro="third_party/firebase_cpp_sdk/libs/android/$module.pro"
	[[ -f "$pro" ]] || { echo "Missing $pro" >&2; exit 1; }
	printf '\n' >> "$stage/aar/proguard.txt"
	cat "$pro" >> "$stage/aar/proguard.txt"
done
rm -f "$output"
(cd "$stage/aar" && zip -qr "$output" .)
