#!/usr/bin/env bash
# Downloads the pinned native dependencies of tools/versions.env into third_party/.
#   godot-cpp            ~25 MB  (git, pinned commit)
#   Firebase C++ SDK     ~1.8 GB zip (dl.google.com)
#   Firebase iOS SDK zip ~340 MB (github.com/firebase/firebase-ios-sdk releases)
#   Google Mobile Ads + UMP iOS ~12 MB (dl.google.com; AdMob module)
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
		echo "warning: no pinned SHA-256 for $1; pin this value in tools/versions.env: $actual"
	elif [ "$actual" != "$2" ]; then
		echo "error: SHA-256 mismatch for $1 (got $actual)" >&2
		rm -f "$1"
		exit 1
	fi
}

# fetch_zip url zip sha256 extracted_dir member-patterns...
# Members extract into extracted_dir's parent; extracted_dir is the archive's root
# folder. extracted_dir/.complete lists the extracted patterns; a different list is redone.
fetch_zip() {
	local url=$1 zip=$2 sha=$3 dir=$4
	shift 4
	[ "$(cat "$dir/.complete" 2>/dev/null)" = "$*" ] && return
	rm -rf "$dir"
	[ -f "$zip" ] || curl --fail --location --silent --show-error --output "$zip" "$url"
	verify "$zip" "$sha"
	mkdir -p "$(dirname "$dir")"
	unzip -q "$zip" "$@" -d "$(dirname "$dir")"
	echo "$*" > "$dir/.complete"
	rm -f "$zip"
}

if [ ! -d third_party/godot-cpp/.git ]; then
	git clone --quiet --filter=blob:none https://github.com/godotengine/godot-cpp.git third_party/godot-cpp
fi
git -C third_party/godot-cpp fetch --quiet origin "$GODOT_CPP_COMMIT"
git -C third_party/godot-cpp checkout --quiet "$GODOT_CPP_COMMIT"

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

# AdMob module, iOS: static xcframeworks that SConstruct links like Firebase's.
ads_dir=third_party/GoogleMobileAds
fetch_zip "$GOOGLE_MOBILE_ADS_IOS_URL" "third_party/GoogleMobileAds-${GOOGLE_MOBILE_ADS_IOS_VERSION}.zip" \
	"$GOOGLE_MOBILE_ADS_IOS_SHA256" "$ads_dir/GoogleMobileAds.xcframework" 'GoogleMobileAds.xcframework/*'
fetch_zip "$GOOGLE_UMP_IOS_URL" "third_party/UserMessagingPlatform-${GOOGLE_UMP_IOS_VERSION}.zip" \
	"$GOOGLE_UMP_IOS_SHA256" "$ads_dir/UserMessagingPlatform.xcframework" 'UserMessagingPlatform.xcframework/*'
# Both SDKs ship their privacy manifest inside the static framework. CocoaPods
# copies it into the app as these resource bundles; the iOS export does the same.
for pair in GoogleMobileAds:GoogleMobileAdsResources UserMessagingPlatform:UserMessagingPlatformResources; do
	framework=${pair%%:*}
	name=${pair##*:}
	bundle="$ads_dir/resources/$name.bundle"
	# Recreated every run: the archive's files are read-only on macOS, so a
	# copy left in the persistent CI cache cannot be overwritten.
	rm -rf "$bundle"
	mkdir -p "$bundle"
	cp "$ads_dir/$framework.xcframework/ios-arm64/$framework.framework/PrivacyInfo.xcprivacy" "$bundle/"
	chmod u+w "$bundle/PrivacyInfo.xcprivacy"
	cat > "$bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.godotengine.godotfirebase.$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
done

du -sh third_party/* | sed 's/^/third_party size: /'
df -h third_party | tail -1 | sed 's/^/disk: /'
