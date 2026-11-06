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
# The SDK-facing Java bridges compile against pinned API jars. They remain
# compile-only: Gradle dependencies are added by the game export plugin.
if [[ -z "${GRADLE:-}" ]]; then
	# Official gradle-9.3.1-wrapper.jar SHA-256; update with gradle-wrapper.properties.
	wrapper_sha=$(shasum -a 256 android/gradle/wrapper/gradle-wrapper.jar | cut -d' ' -f1)
	[[ "$wrapper_sha" == b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13 ]] || { echo "Unexpected gradle-wrapper.jar SHA-256: $wrapper_sha" >&2; exit 1; }
fi
"${GRADLE:-$PWD/android/gradlew}" --no-daemon -p android bridgeClasspath
classpath="$sdk/platforms/android-35/android.jar"
for dependency in android/build/bridge-classpath/*.jar; do
	classpath="$classpath:$dependency"
done
javac --release 8 -Xlint:-options -cp "$classpath" -d "$stage/classes" android/src/org/godotengine/godotfirebase/*.java
jar --create --file "$stage/aar/classes.jar" -C "$stage/classes" .
cp android/AndroidManifest.xml "$stage/aar/AndroidManifest.xml"
touch "$stage/aar/R.txt"
printf '%s\n' '-keep class org.godotengine.godotfirebase.FirebaseBridge { *; }' '-keep class org.godotengine.godotfirebase.FirebaseAuthBridge { *; }' '-keep class org.godotengine.godotfirebase.FirebaseCrashlyticsBridge { *; }' > "$stage/aar/proguard.txt"
# The shared AAR contains optional bridges. Product/provider selection adds their
# runtime dependencies; omitted bridges are never invoked. Keep suppression scoped
# to those optional APIs so unrelated missing dependencies still fail R8.
printf '%s\n' '-dontwarn androidx.credentials.**' '-dontwarn com.google.android.libraries.identity.googleid.**' '-dontwarn com.google.android.gms.games.**' '-dontwarn com.google.firebase.crashlytics.**' >> "$stage/aar/proguard.txt"
for module in app auth firestore storage database functions analytics remote_config; do
	pro="third_party/firebase_cpp_sdk/libs/android/$module.pro"
	[[ -f "$pro" ]] || { echo "Missing $pro" >&2; exit 1; }
	printf '\n' >> "$stage/aar/proguard.txt"
	cat "$pro" >> "$stage/aar/proguard.txt"
done
rm -f "$output"
(cd "$stage/aar" && zip -qr "$output" .)
