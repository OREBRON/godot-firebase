#!/usr/bin/env bash
# Downloads the pinned native dependencies of tools/versions.env into third_party/.
#   godot-cpp            ~25 MB  (git, pinned commit)
#   Firebase C++ SDK     ~1.8 GB zip (dl.google.com)
#   Firebase iOS SDK zip ~340 MB (github.com/firebase/firebase-ios-sdk releases)
#   Firebase Android BoM  ~5 KB  (dl.google.com), only read by tests
# Only iOS (device + arm64 simulator) and Android arm64-v8a files of the used
# modules are extracted; archives are verified, then deleted.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/versions.env
mkdir -p third_party
touch third_party/.gdignore

verify() { # file expected_sha256
	local actual
	actual=$(shasum -a 256 "$1" | cut -d' ' -f1)
	if [ -z "$2" ]; then
		echo "error: no pinned SHA-256 for $1; pin this value in tools/versions.env: $actual" >&2
		rm -f "$1"
		exit 1
	elif [ "$actual" != "$2" ]; then
		echo "error: SHA-256 mismatch for $1 (got $actual)" >&2
		rm -f "$1"
		exit 1
	fi
}

# download url file: curl writes file.part, renamed only when it finished, so an
# interrupted download is never taken for a finished one; the next run starts over.
download() {
	[ -f "$2" ] && return
	rm -f "$2.part"
	curl --fail --location --silent --show-error --output "$2.part" "$1"
	mv "$2.part" "$2"
}

# fetch_zip url zip sha256 extracted_dir member-patterns...
# extracted_dir/.complete lists the archive, its verified SHA-256 and the patterns;
# a different version, pin or list is redone.
fetch_zip() {
	local url=$1 zip=$2 sha=$3 dir=$4
	shift 4
	local marker
	marker="$(basename "$zip") $sha $*"
	[ "$(cat "$dir/.complete" 2>/dev/null)" = "$marker" ] && return
	rm -rf "$dir"
	download "$url" "$zip"
	verify "$zip" "$sha"
	unzip -q "$zip" "$@" -d third_party
	echo "$marker" > "$dir/.complete"
	rm -f "$zip"
}

godot_cpp_url=https://github.com/godotengine/godot-cpp.git
if [ "$(git -C third_party/godot-cpp remote get-url origin 2>/dev/null)" != "$godot_cpp_url" ]; then
	rm -rf third_party/godot-cpp
	git clone --quiet --filter=blob:none "$godot_cpp_url" third_party/godot-cpp
fi
git -C third_party/godot-cpp fetch --quiet origin "$GODOT_CPP_COMMIT"
git -C third_party/godot-cpp reset --quiet --hard "$GODOT_CPP_COMMIT"
# Ignored build products stay so CI reuses cached godot-cpp objects; release CI cleans them with -x.
git -C third_party/godot-cpp clean -ffdq

cpp_members=('firebase_cpp_sdk/include/*' firebase_cpp_sdk/Android/firebase_dependencies.gradle firebase_cpp_sdk/generate_xml_from_google_services_json.py)
for lib in app auth firestore storage database functions analytics remote_config; do
	for dir in ios/device-arm64 ios/simulator-arm64 android/arm64-v8a; do
		cpp_members+=("firebase_cpp_sdk/libs/$dir/libfirebase_$lib.a")
	done
	cpp_members+=("firebase_cpp_sdk/libs/android/$lib.pro")
done
fetch_zip "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_${FIREBASE_CPP_VERSION}.zip" \
	"third_party/firebase_cpp_sdk_${FIREBASE_CPP_VERSION}.zip" "$FIREBASE_CPP_SHA256" third_party/firebase_cpp_sdk \
	"${cpp_members[@]}"

fetch_zip "https://github.com/firebase/firebase-ios-sdk/releases/download/${FIREBASE_IOS_VERSION}/Firebase.zip" \
	"third_party/Firebase-${FIREBASE_IOS_VERSION}.zip" "$FIREBASE_IOS_SHA256" third_party/Firebase \
	'Firebase/FirebaseAnalytics/*' 'Firebase/FirebaseAuth/*' 'Firebase/FirebaseFirestore/*' \
	'Firebase/FirebaseStorage/*' 'Firebase/FirebaseDatabase/*' 'Firebase/FirebaseFunctions/*' \
	'Firebase/FirebaseRemoteConfig/*' 'Firebase/FirebaseCrashlytics/*'

bom="third_party/firebase-bom-${FIREBASE_ANDROID_BOM_VERSION}.pom"
download "https://dl.google.com/dl/android/maven2/com/google/firebase/firebase-bom/${FIREBASE_ANDROID_BOM_VERSION}/$(basename "$bom")" \
	"$bom"
verify "$bom" "$FIREBASE_ANDROID_BOM_SHA256"

du -sh third_party/* | sed 's/^/third_party size: /'
df -h third_party | tail -1 | sed 's/^/disk: /'
