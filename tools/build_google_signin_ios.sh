#!/usr/bin/env bash
# Build the Google provider's pinned source dependencies, without game config.
# Shared GoogleUtilities/FBLPromises/GTMSessionFetcher remain owned by Firebase.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$PWD"
work="${GOOGLE_SIGNIN_BUILD_DIR:-$repo/build/google-signin-ios}"
output="$repo/third_party/GoogleSignIn"
mkdir -p "$work" "$(dirname "$output")"
command -v pod >/dev/null || { echo "Google Sign-In iOS requires CocoaPods" >&2; exit 1; }
cp tools/google_signin_ios/Podfile tools/google_signin_ios/Podfile.lock "$work/"
fingerprint=$( { cat "$work/Podfile" "$work/Podfile.lock" "$repo/tools/build_google_signin_ios.sh"; xcodebuild -version; printf '%s\n' 'ios15:arm64:sim-arm64-x86_64:Release:distribution'; } | shasum -a 256 | cut -d ' ' -f1)
if [[ -f "$output/.build-id" && "$(cat "$output/.build-id")" == "$fingerprint" ]]; then
    complete=true
    for product in GoogleSignIn AppAuth GTMAppAuth AppCheckCore; do
        for slice in ios-arm64 ios-arm64_x86_64-simulator; do
            [[ -f "$output/$product.xcframework/$slice/$product.framework/$product" ]] || complete=false
        done
    done
    for resource in GoogleSignIn AppAuthCore_Privacy GTMAppAuth_Privacy; do
        [[ -d "$output/resources/$resource.bundle" ]] || complete=false
    done
    if $complete; then
        echo "GoogleSignIn 9.2.0 build is current"
        exit 0
    fi
fi
pod install --deployment --project-directory="$work" > "$work/pod-install.log" 2>&1 || { cat "$work/pod-install.log"; exit 1; }
for sdk in iphoneos iphonesimulator; do
    archs=arm64
    destination='generic/platform=iOS'
    if [[ "$sdk" == iphonesimulator ]]; then
        archs='arm64 x86_64'
        destination='generic/platform=iOS Simulator'
    fi
    xcodebuild -project "$work/Pods/Pods.xcodeproj" -scheme GoogleSignIn \
        -configuration Release -sdk "$sdk" -destination "$destination" \
        -derivedDataPath "$work/DerivedData" SYMROOT="$work/products" \
        SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO \
        ARCHS="$archs" ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 \
        build > "$work/$sdk.log" 2>&1 || { tail -n 100 "$work/$sdk.log"; exit 1; }
done
stage=$(mktemp -d "$repo/third_party/.google-signin.XXXXXX")
trap 'rm -rf "$stage"' EXIT
for product in GoogleSignIn AppAuth GTMAppAuth AppCheckCore; do
    xcodebuild -create-xcframework \
        -framework "$work/products/Release-iphoneos/$product/$product.framework" \
        -framework "$work/products/Release-iphonesimulator/$product/$product.framework" \
        -output "$stage/$product.xcframework" > "$work/$product-package.log" 2>&1 || { cat "$work/$product-package.log"; exit 1; }
done
mkdir -p "$stage/resources"
for resource in 'GoogleSignIn/GoogleSignIn' 'AppAuth/AppAuthCore_Privacy' 'GTMAppAuth/GTMAppAuth_Privacy'; do
    cp -R "$work/products/Release-iphoneos/$resource.bundle" "$stage/resources/"
done
cp "$work/Podfile.lock" "$stage/Podfile.lock"
printf '%s\n' "$fingerprint" > "$stage/.build-id"
# Generated dependency output only. Stage atomically after both architectures succeed.
previous="$repo/third_party/.GoogleSignIn.previous"
rm -rf "$previous"
if [[ -e "$output" ]]; then mv "$output" "$previous"; fi
mv "$stage" "$output"
rm -rf "$previous"
echo "GoogleSignIn 9.2.0 frameworks and resource bundles: $output"
