#!/usr/bin/env bash
# Zips the built addon with only the modules it was built for.
#   tools/package.sh   ->  build/dist/godot-firebase-<modules>.zip
#   (build/dist/godot-firebase.zip when every module is built)
# Unzip into a game's project root; it creates addons/firebase/.
set -euo pipefail
cd "$(dirname "$0")/.."

ADDON=addons/firebase
modules=$(cat "$ADDON/bin/modules.txt")
all_modules=""
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/addons" build/dist
cp -R "$ADDON" "$stage/addons/"
# A module folder holds firebase_<module>.gd; core/, export/ and bin/ do not.
for folder in "$stage/$ADDON"/*/; do
	module=$(basename "$folder")
	[ -f "$folder/firebase_$module.gd" ] || continue
	all_modules+=",$module"
	[[ ",$modules," == *",$module,"* ]] || rm -rf "$folder"
done
find "$stage" -name ".DS_Store" -delete

# Module lists compare as sorted sets, so "auth,storage" and "storage,auth" match.
sorted() { tr ',' '\n' <<<"$1" | sed '/^$/d' | sort | paste -sd, -; }
if [ "$(sorted "$modules")" = "$(sorted "$all_modules")" ]; then
	out="$PWD/build/dist/godot-firebase.zip"
else
	out="$PWD/build/dist/godot-firebase-${modules//,/-}.zip"
fi
rm -f "$out"
(cd "$stage" && zip -qry "$out" addons)
echo "$out"
