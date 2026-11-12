#!/usr/bin/env bash
# Builds addons/firebase/bin/ for the selected modules.
#   tools/build.sh [--modules auth,firestore] [--platforms ios,android,macos,linux,windows]
# Mobile builds need tools/bootstrap.sh. Desktop stubs need only a C compiler.
# SCons runs through uv at SCONS_VERSION of tools/versions.env unless SCONS is set.
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

fail() { echo "$1" >&2; exit 2; }
# Checked before anything is built or written, so a typo cannot rewrite modules.txt.
# Spaces are rejected, not trimmed: package.sh and the Android export read exact names.
platform_list='^(ios|android|macos|linux|windows)(,(ios|android|macos|linux|windows))*$'
module_list='^[a-z][a-z0-9_]*(,[a-z][a-z0-9_]*)*$'
[[ $platforms =~ $platform_list ]] || fail "--platforms takes comma-separated ios,android,macos,linux,windows without spaces, got '$platforms'"
[[ $modules =~ $module_list ]] || fail "--modules takes comma-separated product names without spaces, got '$modules'"
seen=,
for module in ${modules//,/ }; do
	# A product is an API folder, as in package.sh.
	test -f "addons/firebase/$module/firebase_$module.gd" || fail "unknown module '$module': addons/firebase/$module/firebase_$module.gd not found"
	[[ $seen != *",$module,"* ]] || fail "module '$module' is selected twice"
	seen+="$module,"
done

source tools/versions.env
SCONS="${SCONS:-uvx --from scons==$SCONS_VERSION scons}"
mkdir -p build
touch build/.gdignore
BIN=addons/firebase/bin
JOBS=$(python3 -c 'import os; print(os.cpu_count() or 1)')
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
	local host=linux-x86_64
	[ "$(uname -s)" != Darwin ] || host=darwin-x86_64
	local readelf="${LLVM_READELF:-$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-readelf}"
	local strip
	strip="$(dirname "$readelf")/llvm-strip"
	test -x "$readelf" && test -x "$strip" || { echo "Set LLVM_READELF to the build NDK's llvm-readelf (with llvm-strip beside it)" >&2; return 1; }
	mkdir -p "$directory"
	cp "build/android/$stem" "$directory/$stem"
	# The addon ships a stripped library like builds without debug_symbols; DWARF stays in the symbols copy.
	"$strip" --strip-all "$BIN/android/$stem"
	python3 tools/verify_crashlytics_symbols.py android --binary "$BIN/android/$stem" --symbols "$directory/$stem" --readelf "$readelf" --output "$directory/identity.json" >/dev/null
}

if [[ ",$platforms," == *",macos,"* ]]; then
	for arch in arm64 x86_64; do
		python3 tools/build_desktop_stub.py --platform macos --arch "$arch"
	done
fi

for platform in linux windows; do
	if [[ ",$platforms," == *",$platform,"* ]]; then
		python3 tools/build_desktop_stub.py --platform "$platform" --arch x86_64
	fi
done

if [[ ",$platforms," == *",ios,"* ]]; then
	mkdir -p "$BIN/ios"
	for target in template_debug template_release; do
		build ios "$target" arch=arm64 ios_simulator=no
		collect_ios_symbols "$target"
		build ios "$target" arch=arm64 ios_simulator=yes
		collect_ios_symbols "$target" .simulator
		out="$BIN/ios/godot_firebase.ios.$target.xcframework"
		# Prepare framework slices now: Godot would rewrite bare dylib slices on
		# export, losing the SDK signature. package.sh --sign-ios signs last.
		python3 tools/build_ios_xcframework.py --target "$target" --output "$out"
	done

	# Firebase resource bundles (certificates, privacy manifests) of the linked
	# frameworks belong in the app bundle. SConstruct lists them.
	rm -rf "$BIN/ios/resources"
	mkdir -p "$BIN/ios/resources"
	# Apple-optimized PNGs in bundles are not Godot importable; the export plugin
	# reads these bundles directly from disk when creating the iOS app.
	touch "$BIN/ios/resources/.gdignore"
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
