#!/usr/bin/env bash
# Zips the built addon with only the modules it was built for.
#   tools/package.sh   ->  build/dist/godot_firebase-<modules>.zip
# Unzip into a game's project root; it creates addons/godot_firebase/.
set -euo pipefail
cd "$(dirname "$0")/.."

ADDON=addons/godot_firebase
modules=$(cat "$ADDON/bin/modules.txt")
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/addons" build/dist
cp -R "$ADDON" "$stage/addons/"
# A module folder holds firebase_<module>.gd; core/, export/ and bin/ do not.
for folder in "$stage/$ADDON"/*/; do
	module=$(basename "$folder")
	[ -f "$folder/firebase_$module.gd" ] || continue
	[[ ",$modules," == *",$module,"* ]] || rm -rf "$folder"
done
find "$stage" -name ".DS_Store" -delete

out="$PWD/build/dist/godot_firebase-${modules//,/-}.zip"
rm -f "$out"
(cd "$stage" && zip -qry "$out" addons)
echo "$out"
