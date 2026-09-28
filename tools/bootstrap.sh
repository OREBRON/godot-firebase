#!/usr/bin/env bash
# Downloads the pinned native dependencies of tools/versions.env into third_party/.
#   godot-cpp            ~25 MB  (git, pinned commit)
#   Firebase C++ SDK     ~1.8 GB (dl.google.com)
#   Firebase iOS SDK zip ~340 MB (github.com/firebase/firebase-ios-sdk releases)
# Existing downloads are reused. Archives are checked against their SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/versions.env
mkdir -p third_party

verify() { # file expected_sha256
	local actual
	actual=$(shasum -a 256 "$1" | cut -d' ' -f1)
	if [ -z "$2" ]; then
		echo "warning: no pinned SHA-256 for $1; pin this value in tools/versions.env: $actual"
	elif [ "$actual" != "$2" ]; then
		echo "error: SHA-256 mismatch for $1 (got $actual)" >&2
		exit 1
	fi
}

fetch_zip() { # url file sha256 extracted_dir
	if [ -d "$4" ]; then
		return
	fi
	[ -f "$2" ] || curl --fail --location --output "$2" "$1"
	verify "$2" "$3"
	unzip -q "$2" -d third_party
}

if [ ! -d third_party/godot-cpp/.git ]; then
	git clone --filter=blob:none https://github.com/godotengine/godot-cpp.git third_party/godot-cpp
fi
git -C third_party/godot-cpp fetch --quiet origin "$GODOT_CPP_COMMIT"
git -C third_party/godot-cpp checkout --quiet "$GODOT_CPP_COMMIT"

fetch_zip "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_${FIREBASE_CPP_VERSION}.zip" \
	"third_party/firebase_cpp_sdk_${FIREBASE_CPP_VERSION}.zip" "$FIREBASE_CPP_SHA256" third_party/firebase_cpp_sdk

fetch_zip "https://github.com/firebase/firebase-ios-sdk/releases/download/${FIREBASE_IOS_VERSION}/Firebase.zip" \
	"third_party/Firebase-${FIREBASE_IOS_VERSION}.zip" "$FIREBASE_IOS_SHA256" third_party/Firebase

echo "third_party ready: godot-cpp $GODOT_CPP_COMMIT, Firebase C++ $FIREBASE_CPP_VERSION, Firebase iOS $FIREBASE_IOS_VERSION"
