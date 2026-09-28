#!/usr/bin/env bash
# Downloads the pinned native dependencies of tools/versions.env into third_party/.
#   godot-cpp            ~25 MB  (git, pinned commit)
#   Firebase C++ SDK     ~1.8 GB zip (dl.google.com)
#   Firebase iOS SDK zip ~340 MB (github.com/firebase/firebase-ios-sdk releases)
# Only the Apple parts are extracted; archives are verified, then deleted.
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
		rm -f "$1"
		exit 1
	fi
}

# fetch_zip url zip sha256 extracted_dir member-patterns...
# extracted_dir/.complete marks a finished extraction; anything else is redone.
fetch_zip() {
	local url=$1 zip=$2 sha=$3 dir=$4
	shift 4
	[ -f "$dir/.complete" ] && return
	rm -rf "$dir"
	[ -f "$zip" ] || curl --fail --location --silent --show-error --output "$zip" "$url"
	verify "$zip" "$sha"
	unzip -q "$zip" "$@" -d third_party
	touch "$dir/.complete"
	rm -f "$zip"
}

if [ ! -d third_party/godot-cpp/.git ]; then
	git clone --quiet --filter=blob:none https://github.com/godotengine/godot-cpp.git third_party/godot-cpp
fi
git -C third_party/godot-cpp fetch --quiet origin "$GODOT_CPP_COMMIT"
git -C third_party/godot-cpp checkout --quiet "$GODOT_CPP_COMMIT"

fetch_zip "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_${FIREBASE_CPP_VERSION}.zip" \
	"third_party/firebase_cpp_sdk_${FIREBASE_CPP_VERSION}.zip" "$FIREBASE_CPP_SHA256" third_party/firebase_cpp_sdk \
	'firebase_cpp_sdk/include/*' 'firebase_cpp_sdk/libs/darwin/*' 'firebase_cpp_sdk/xcframeworks/*'

fetch_zip "https://github.com/firebase/firebase-ios-sdk/releases/download/${FIREBASE_IOS_VERSION}/Firebase.zip" \
	"third_party/Firebase-${FIREBASE_IOS_VERSION}.zip" "$FIREBASE_IOS_SHA256" third_party/Firebase \
	'Firebase/FirebaseAnalytics/*' 'Firebase/FirebaseAuth/*' 'Firebase/FirebaseFirestore/*'

du -sh third_party/* | sed 's/^/third_party size: /'
df -h third_party | tail -1 | sed 's/^/disk: /'
