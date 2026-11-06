#!/usr/bin/env bash
# Install the CocoaPods version recorded by the Google Sign-In lockfile for CI.
set -euo pipefail
cd "$(dirname "$0")/.."

# The self-hosted runner cannot use ruby/setup-ruby's fixed /Users/runner
# toolcache path. Use a recent Homebrew Ruby when macOS provides only Ruby 2.6.
if ! ruby -rrubygems -e 'exit(Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3") ? 0 : 1)'; then
    command -v brew >/dev/null || { echo 'Homebrew is required to install Ruby 3.3 on this runner' >&2; exit 1; }
    ruby_prefix=$(brew --prefix ruby@3.3)
    if [[ ! -x "$ruby_prefix/bin/ruby" ]]; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew install ruby@3.3
    fi
    export PATH="$ruby_prefix/bin:$PATH"
    echo "$ruby_prefix/bin" >> "$GITHUB_PATH"
fi
ruby --version

version=$(awk '/^COCOAPODS:/{print $2}' tools/google_signin_ios/Podfile.lock)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Podfile.lock has no CocoaPods version' >&2; exit 1; }
source tools/versions.env
gem_dir="$RUNNER_TEMP/godot-firebase-cocoapods"
fetch_dir=$(mktemp -d)
trap 'rm -rf "$fetch_dir"' EXIT
(cd "$fetch_dir" && gem fetch cocoapods --version "$version")
gem_file="$fetch_dir/cocoapods-$version.gem"
actual_sha=$(shasum -a 256 "$gem_file" | cut -d' ' -f1)
[[ "$actual_sha" == "$COCOAPODS_SHA256" ]] || { echo "SHA-256 mismatch for cocoapods-$version.gem (got $actual_sha); update COCOAPODS_SHA256 in tools/versions.env with the Podfile.lock version" >&2; exit 1; }
# Only the cocoapods gem itself is verified; its dependencies still resolve from rubygems.org unpinned.
gem install "$gem_file" --no-document --install-dir "$gem_dir"
actual=$(GEM_HOME="$gem_dir" "$gem_dir/bin/pod" --version)
[[ "$actual" == "$version" ]] || { echo "Expected CocoaPods $version; got $actual" >&2; exit 1; }
echo "GEM_HOME=$gem_dir" >> "$GITHUB_ENV"
echo "$gem_dir/bin" >> "$GITHUB_PATH"
echo "CocoaPods $version ready at $gem_dir/bin/pod"
