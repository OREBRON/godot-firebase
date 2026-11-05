#!/usr/bin/env bash
# Builds, signs and publishes the godot-firebase.zip release from this Mac. CI only
# builds and tests; the Apple signing key never leaves the releaser's Keychain.
#   tools/release.sh v1.0.0
# Needs IOS_SIGNING_IDENTITY and IOS_SIGNING_TEAM_ID (IOS_SIGNING_KEYCHAIN optional),
# ANDROID_HOME with platform 35 and NDK 28.1.13356709, JDK 17 and an authenticated gh.
# The tag is v<plugin.cfg version>; a published release is never replaced.
set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:?usage: tools/release.sh <tag>}"
version=$(sed -n 's/^version="\(.*\)"$/\1/p' addons/firebase/plugin.cfg)
test "$tag" = "v$version" || { echo "Tag $tag does not match plugin.cfg version $version" >&2; exit 1; }
# Shipped ZIPs and Crashlytics symbols must stay tied to one build; bump the version instead.
! gh release view "$tag" >/dev/null 2>&1 || { echo "Release $tag already exists; bump plugin.cfg version" >&2; exit 1; }
source tools/versions.env
modules="auth,firestore,storage,database,functions,analytics,remote_config,crashlytics"

# The published binaries must be built from exactly the tagged, committed sources.
test "$(git rev-parse HEAD)" = "$(git rev-parse "$tag^{commit}")" || { echo "Check out $tag first" >&2; exit 1; }
test -z "$(git status --porcelain --untracked-files=no)" || { echo "Commit or stash local changes first" >&2; exit 1; }
git lfs pull

python3 tools/ios_signing.py check-identity
python3 tests/test_ios_signing.py
tools/bootstrap.sh
tools/run_tests.sh
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
gh release create "$tag" "${assets[@]}" --verify-tag --generate-notes \
	--title "$version — Godot $GODOT_VERSION · Firebase C++ $FIREBASE_CPP_VERSION"
cat build/dist/SHA256SUMS.txt
