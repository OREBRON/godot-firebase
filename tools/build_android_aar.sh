#!/usr/bin/env bash
# Package the Java bridge, Firebase configuration and C++ SDK keep rules.
set -euo pipefail
cd "$(dirname "$0")/.."

json=$1
package_name=$2
modules=$3
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ ! -f "$json" || -z "$package_name" || ! -f "$sdk/platforms/android-35/android.jar" ]]; then
	echo "Android AAR needs google-services.json, an Android package name and SDK platform 35" >&2
	exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
output="${ANDROID_AAR_OUTPUT:-$PWD/addons/firebase/bin/android/godot_firebase.aar}"
mkdir -p "$stage/classes" "$stage/aar/res/values" addons/firebase/bin/android
javac --release 8 -Xlint:-options -cp "$sdk/platforms/android-35/android.jar" -d "$stage/classes" android/src/org/godotengine/godotfirebase/FirebaseBridge.java
jar --create --file "$stage/aar/classes.jar" -C "$stage/classes" .
python3 third_party/firebase_cpp_sdk/generate_xml_from_google_services_json.py \
	-i "$json" -p "$package_name" -o "$stage/aar/res/values/googleservices.xml"
cp android/AndroidManifest.xml "$stage/aar/AndroidManifest.xml"
touch "$stage/aar/R.txt"
printf '%s\n' '-keep class org.godotengine.godotfirebase.FirebaseBridge { *; }' > "$stage/aar/proguard.txt"
for module in app ${modules//,/ }; do
	pro="third_party/firebase_cpp_sdk/libs/android/$module.pro"
	[[ -f "$pro" ]] || { echo "Missing $pro" >&2; exit 1; }
	printf '\n' >> "$stage/aar/proguard.txt"
	cat "$pro" >> "$stage/aar/proguard.txt"
done
rm -f "$output"
(cd "$stage/aar" && zip -qr "$output" .)