#!/usr/bin/env bash
# Builds addons/firebase/bin/ for the selected modules.
#   tools/build.sh [--modules auth,firestore] [--platforms ios,android,macos]
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
mkdir -p build
touch build/.gdignore
BIN=addons/firebase/bin
JOBS=$(sysctl -n hw.ncpu)
symbols_root="build/symbols/${modules//,/-}"
crashlytics_symbols=false
[[ ",$modules," != *",crashlytics,"* ]] || crashlytics_symbols=true

# Auth's source-built iOS dependencies carry no game identifiers. The helper
# checks pinned inputs and installed CocoaPods; it never installs global tools.
if [[ ",$platforms," == *",ios,"* && ",$modules," == *",auth,"* ]]; then
	tools/build_google_signin_ios.sh
fi

build() { # platform target extra-args...
	if $crashlytics_symbols; then
		$SCONS -j"$JOBS" platform="$1" target="$2" modules="$modules" debug_symbols=yes "${@:3}"
	else
		$SCONS -j"$JOBS" platform="$1" target="$2" modules="$modules" "${@:3}"
	fi
}

collect_ios_symbols() { # target, optional .simulator suffix
	$crashlytics_symbols || return 0
	local stem="libgodot_firebase.ios.$1${2:-}.dylib"
	local directory="$symbols_root/ios/$1${2:-}"
	mkdir -p "$directory"
	cp "build/ios/$stem" "$directory/$stem"
	rm -rf "$directory/$stem.dSYM"
	xcrun dsymutil "build/ios/$stem" -o "$directory/$stem.dSYM"
	python3 tools/verify_crashlytics_symbols.py ios --binary "$directory/$stem" --symbols "$directory/$stem.dSYM" --output "$directory/identity.json" >/dev/null
}

collect_android_symbols() { # target
	$crashlytics_symbols || return 0
	local stem="libgodot_firebase.android.$1.so"
	local directory="$symbols_root/android/$1/arm64-v8a"
	local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
	local ndk="$sdk/ndk/${NDK_VERSION:-28.1.13356709}"
	local readelf="${LLVM_READELF:-$ndk/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf}"
	test -x "$readelf" || { echo "Set LLVM_READELF to the build NDK's llvm-readelf" >&2; return 1; }
	mkdir -p "$directory"
	cp "build/android/$stem" "$directory/$stem"
	python3 tools/verify_crashlytics_symbols.py android --binary "$BIN/android/$stem" --symbols "$directory/$stem" --readelf "$readelf" --output "$directory/identity.json" >/dev/null
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
		collect_ios_symbols "$target"
		build ios "$target" arch=arm64 ios_simulator=yes
		collect_ios_symbols "$target" .simulator
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
	mkdir -p "$BIN/android"
	for target in template_debug template_release; do
		build android "$target" arch=arm64 ndk_version="${NDK_VERSION:-28.1.13356709}"
		cp "build/android/libgodot_firebase.android.$target.so" "$BIN/android/"
		collect_android_symbols "$target"
	done
	bash tools/build_android_aar.sh
fi

echo "$modules" > "$BIN/modules.txt"
echo "built modules [$modules] for [$platforms] into $BIN"
$crashlytics_symbols && echo "Verified native symbols: $symbols_root (upload is explicit; game R8 mapping is not generated here)"
exit 0
