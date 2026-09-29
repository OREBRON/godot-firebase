#!/usr/bin/env bash
# Builds addons/firebase/bin/ for the selected modules.
#   tools/build.sh [--modules auth,firestore] [--platforms ios,android,macos]
# Needs tools/bootstrap.sh first. SCons runs through uv unless SCONS is set.
set -euo pipefail
cd "$(dirname "$0")/.."

modules="auth,firestore"
platforms="ios,macos"
google_services=""
android_package=""
while [ $# -gt 0 ]; do
	case "$1" in
		--modules) modules="$2"; shift 2 ;;
		--platforms) platforms="$2"; shift 2 ;;
		--google-services) google_services="$2"; shift 2 ;;
		--android-package) android_package="$2"; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

SCONS="${SCONS:-uvx scons}"
BIN=addons/firebase/bin
JOBS=$(sysctl -n hw.ncpu)

build() { # platform target extra-args...
	$SCONS -j"$JOBS" platform="$1" target="$2" modules="$modules" "${@:3}"
}

if [[ ",$platforms," == *",macos,"* ]]; then
	mkdir -p "$BIN/macos"
	for target in template_debug template_release; do
		build macos "$target" arch=arm64
		cp "build/macos/libgodot_firebase.macos.$target.dylib" "$BIN/macos/"
	done
fi

if [[ ",$platforms," == *",ios,"* ]]; then
	mkdir -p "$BIN/ios"
	for target in template_debug template_release; do
		build ios "$target" arch=arm64 ios_simulator=no
		build ios "$target" arch=arm64 ios_simulator=yes
		out="$BIN/ios/godot_firebase.ios.$target.xcframework"
		rm -rf "$out"
		xcodebuild -create-xcframework \
			-library "build/ios/libgodot_firebase.ios.$target.dylib" \
			-library "build/ios/libgodot_firebase.ios.$target.simulator.dylib" \
			-output "$out"
	done

	# Firebase resource bundles (certificates, privacy manifests) of the linked
	# frameworks belong in the app bundle. SConstruct lists them.
	rm -rf "$BIN/ios/resources"
	mkdir -p "$BIN/ios/resources"
	while IFS= read -r bundle; do
		cp -R "$bundle" "$BIN/ios/resources/"
	done < build/ios/resource_bundles.txt
fi

if [[ ",$platforms," == *",android,"* ]]; then
	if [[ -z "$google_services" || -z "$android_package" ]]; then
		echo "Android build needs --google-services and --android-package" >&2
		exit 2
	fi
	mkdir -p "$BIN/android"
	for target in template_debug template_release; do
		build android "$target" arch=arm64 ndk_version="${NDK_VERSION:-28.1.13356709}"
		cp "build/android/libgodot_firebase.android.$target.so" "$BIN/android/"
	done
	bash tools/build_android_aar.sh "$google_services" "$android_package" "$modules"
fi

echo "$modules" > "$BIN/modules.txt"
echo "built modules [$modules] for [$platforms] into $BIN"
