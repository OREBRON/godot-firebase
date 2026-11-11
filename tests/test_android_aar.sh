#!/usr/bin/env bash
# The bridge AAR is the same for every game: no Firebase configuration inside.
set -euo pipefail
cd "$(dirname "$0")/.."

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ANDROID_AAR_OUTPUT="$stage/firebase.aar" bash tools/build_android_aar.sh
if unzip -l "$stage/firebase.aar" | grep -q -E 'res/|google-services|googleservices'; then
	echo "AAR must not contain Firebase configuration or resources" >&2
	exit 1
fi
for keep in org.godotengine.godotfirebase.FirebaseBridge org.godotengine.godotfirebase.FirebaseAuthBridge org.godotengine.godotfirebase.FirebaseCrashlyticsBridge com.google.firebase.firestore.FirebaseFirestore com.google.firebase.functions com.google.firebase.analytics com.google.firebase.remoteconfig; do
	unzip -p "$stage/firebase.aar" proguard.txt | grep -q "$keep"
done
unzip -p "$stage/firebase.aar" classes.jar > "$stage/classes.jar"
for bridge in FirebaseBridge FirebaseAuthBridge FirebaseCrashlyticsBridge; do
	jar tf "$stage/classes.jar" | grep -q "org/godotengine/godotfirebase/$bridge.class"
done
javap -cp "$stage/classes.jar" org.godotengine.godotfirebase.FirebaseBridge | grep -q 'initialize(android.app.Activity, java.lang.String, java.lang.String, java.lang.String, java.lang.String, java.lang.String, java.lang.String)'
# Activity-scoped Task listeners are dropped at onStop, so Play Games sign-in would never complete.
games=$(javap -c -p -cp "$stage/classes.jar" 'org.godotengine.godotfirebase.FirebaseAuthBridge$GamesProvider')
if grep -q 'addOnCompleteListener:(Landroid/app/Activity;' <<<"$games" || [[ $(grep -c 'addOnCompleteListener:(Lcom/google/android/gms/tasks/OnCompleteListener;)' <<<"$games") -ne 3 ]]; then
	echo "Play Games sign-in listeners must not be Activity-scoped" >&2
	exit 1
fi
echo "test_android_aar.sh: ok"
