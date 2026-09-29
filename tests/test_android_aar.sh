#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ANDROID_AAR_OUTPUT="$stage/firebase.aar" bash tools/build_android_aar.sh \
	tests/fixtures/google-services.json org.godotengine.firebase.test auth,firestore
unzip -p "$stage/firebase.aar" res/values/googleservices.xml | grep -q 'name="google_app_id"'
unzip -p "$stage/firebase.aar" proguard.txt | grep -q 'com.google.firebase.firestore.FirebaseFirestore'
unzip -p "$stage/firebase.aar" proguard.txt | grep -q 'org.godotengine.godotfirebase.FirebaseBridge'
unzip -p "$stage/firebase.aar" classes.jar > "$stage/classes.jar"
jar tf "$stage/classes.jar" | grep -q 'org/godotengine/godotfirebase/FirebaseBridge.class'
if ANDROID_AAR_OUTPUT="$stage/invalid.aar" bash tools/build_android_aar.sh \
	tests/fixtures/google-services.json org.godotengine.wrong auth > /dev/null 2>&1; then
	echo "Wrong Android package name must fail" >&2
	exit 1
fi