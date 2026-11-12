#!/usr/bin/env bash
# Builds, signs and publishes the godot-firebase.zip release from this Mac. CI only
# builds and tests; the Apple signing key never leaves the releaser's Keychain.
#   tools/release.sh v1.0.0
# Needs IOS_SIGNING_IDENTITY and IOS_SIGNING_TEAM_ID (IOS_SIGNING_KEYCHAIN optional),
# ANDROID_HOME with the Android platform and NDK of tools/versions.env, JDK 17, CocoaPods, uv
# and an authenticated gh. These and the pushed tag are checked before anything is built.
# The tag is v<plugin.cfg version>; a published release is never replaced.
set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:?usage: tools/release.sh <tag>}"
version=$(sed -n 's/^version="\(.*\)"$/\1/p' addons/firebase/plugin.cfg)
test "$tag" = "v$version" || { echo "Tag $tag does not match plugin.cfg version $version" >&2; exit 1; }
# Shipped ZIPs and Crashlytics symbols must stay tied to one build; bump the version instead.
# Only gh's "release not found" means no release; a login or network error must stop here too.
if release=$(gh release view "$tag" 2>&1); then
	echo "Release $tag already exists; bump plugin.cfg version" >&2; exit 1
elif [ "$release" != "release not found" ]; then
	printf 'gh could not check release %s (gh auth login?):\n%s\n' "$tag" "$release" >&2; exit 1
fi
source tools/versions.env
modules="auth,firestore,storage,database,functions,analytics,remote_config,crashlytics"

# The published binaries must be built from exactly the tagged, committed sources.
test "$(git rev-parse HEAD)" = "$(git rev-parse "$tag^{commit}")" || { echo "Check out $tag first" >&2; exit 1; }
# gh --verify-tag below only checks that the tag exists on origin; it must also be the built commit.
# Checked before the build so a forgotten push fails fast, and again right before the upload.
check_origin_tag() {
	local remote_tag
	remote_tag=$(git ls-remote origin "refs/tags/$tag^{}" | cut -f1)
	test -n "$remote_tag" || remote_tag=$(git ls-remote origin "refs/tags/$tag" | cut -f1)
	test "$remote_tag" = "$(git rev-parse HEAD)" || { echo "origin tag $tag is missing or not at HEAD; push $tag first" >&2; exit 1; }
}
check_origin_tag
# Tools of the build below, which would otherwise fail only after the tests or the iOS builds.
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
ndk="$sdk/ndk/${NDK_VERSION:-$ANDROID_NDK_VERSION}"
test -f "$sdk/platforms/android-$ANDROID_PLATFORM_VERSION/android.jar" || { echo "Android SDK platform $ANDROID_PLATFORM_VERSION is missing; set ANDROID_HOME" >&2; exit 1; }
test -d "$ndk" || { echo "Android NDK $ndk is missing" >&2; exit 1; }
javac -version >/dev/null 2>&1 || { echo "JDK 17 is missing" >&2; exit 1; }
command -v pod >/dev/null || { echo "CocoaPods (pod) is missing" >&2; exit 1; }
test -n "${SCONS:-}" || command -v uvx >/dev/null || { echo "uv (uvx) is missing; tools/build.sh runs SCons through it" >&2; exit 1; }
# Tracked changes block the release, except the two macOS editor stubs: the macOS build below
# rewrites them, and their bytes follow the local Xcode, so any earlier build leaves them modified.
test -z "$(git status --porcelain --untracked-files=no -- . ':!addons/firebase/bin/macos/*.dylib')" || { echo "Commit or stash local changes first" >&2; exit 1; }
# SConstruct and the AAR glob sources and package.sh ships all of addons/firebase, so
# untracked and ignored files are inputs too. The build regenerates the mobile outputs;
# only SCons objects and Finder metadata (never linked or packaged) may remain.
rm -rf addons/firebase/bin/ios addons/firebase/bin/android addons/firebase/bin/modules.txt
stray=$(git ls-files --others -- src addons/firebase SConstruct tools android \
	':!*.o' ':!*.os' ':!*.os.tmp' ':!*/.DS_Store' ':!android/.gradle' ':!android/build')
test -z "$stray" || { printf 'Remove files that are not part of %s:\n%s\n' "$tag" "$stray" >&2; exit 1; }
git lfs pull

python3 tools/ios_signing.py check-identity
python3 tests/test_ios_signing.py
tools/bootstrap.sh
tools/run_tests.sh
bash tests/test_android_aar.sh
tools/build.sh --platforms ios,android,macos --modules "$modules"
test "$(cat addons/firebase/bin/modules.txt)" = "$modules"
tools/run_tests.sh
package_path="$(tools/package.sh --sign-ios)"
test "$(basename "$package_path")" = godot-firebase.zip
python3 tests/test_sdk_capability_packages.py --smoke-package build/dist/godot-firebase.zip

# Symbols stay a separate asset so the addon ZIP does not grow.
# Only this run's selection: other build/symbols dirs were not rebuilt or verified here.
symbols_dir="symbols/${modules//,/-}"
test -d "build/$symbols_dir" || { echo "Missing build/$symbols_dir" >&2; exit 1; }
rm -f build/dist/godot-firebase-symbols.zip
(cd build && zip -qry dist/godot-firebase-symbols.zip "$symbols_dir")
(cd build/dist && shasum -a 256 godot-firebase.zip godot-firebase-symbols.zip > SHA256SUMS.txt)
assets=(build/dist/godot-firebase.zip build/dist/godot-firebase-symbols.zip build/dist/SHA256SUMS.txt)
# The tag can move during the build.
check_origin_tag
gh release create "$tag" "${assets[@]}" --verify-tag --generate-notes \
	--title "$version — Godot $GODOT_VERSION · Firebase C++ $FIREBASE_CPP_VERSION"
cat build/dist/SHA256SUMS.txt
