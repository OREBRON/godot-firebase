#!/usr/bin/env bash
# Builds addons/godot_firebase/bin/ for the selected modules.
#   tools/build.sh [--modules auth,firestore] [--platforms ios,macos]
# Needs tools/bootstrap.sh first. SCons runs through uv unless SCONS is set.
set -euo pipefail
cd "$(dirname "$0")/.."

modules="auth,firestore"
platforms="ios,macos"
while [ $# -gt 0 ]; do
	case "$1" in
		--modules) modules="$2"; shift 2 ;;
		--platforms) platforms="$2"; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

SCONS="${SCONS:-uvx scons}"
BIN=addons/godot_firebase/bin
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

	# Firebase resource bundles (certificates, privacy manifests) belong in the app bundle.
	folders=(third_party/Firebase/FirebaseAnalytics)
	[[ ",$modules," == *",auth,"* ]] && folders+=(third_party/Firebase/FirebaseAuth)
	[[ ",$modules," == *",firestore,"* ]] && folders+=(third_party/Firebase/FirebaseFirestore)
	rm -rf "$BIN/ios/resources"
	mkdir -p "$BIN/ios/resources"
	find "${folders[@]}" -path "*ios-arm64/*" -name "*.bundle" -type d -prune -exec cp -R {} "$BIN/ios/resources/" \;
fi

echo "$modules" > "$BIN/modules.txt"
echo "built modules [$modules] for [$platforms] into $BIN"
