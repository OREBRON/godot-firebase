#!/usr/bin/env bash
# Install the CocoaPods version recorded by the Google Sign-In lockfile for CI.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(awk '/^COCOAPODS:/{print $2}' tools/google_signin_ios/Podfile.lock)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Podfile.lock has no CocoaPods version' >&2; exit 1; }
gem_dir="$RUNNER_TEMP/godot-firebase-cocoapods"
gem install cocoapods --version "$version" --no-document --install-dir "$gem_dir"
actual=$(GEM_HOME="$gem_dir" "$gem_dir/bin/pod" --version)
[[ "$actual" == "$version" ]] || { echo "Expected CocoaPods $version; got $actual" >&2; exit 1; }
echo "GEM_HOME=$gem_dir" >> "$GITHUB_ENV"
echo "$gem_dir/bin" >> "$GITHUB_PATH"
echo "CocoaPods $version ready at $gem_dir/bin/pod"
