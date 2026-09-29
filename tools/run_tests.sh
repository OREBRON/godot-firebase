#!/usr/bin/env bash
# Runs every tests/test_*.gd headless. Exits non-zero when any test fails.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --editor --quit >/dev/null 2>&1 # builds the class_name cache
failed=0
for test in tests/test_*.gd; do
	output=$(perl -e 'alarm shift; exec @ARGV' 60 "$GODOT" --headless --script "res://$test" 2>&1)
	status=$?
	echo "$output" | grep -E "^(test_|SCRIPT ERROR|ERROR)" | grep -v -E "GDExtension|godot_firebase\.gdextension|libgodot_firebase"
	# A parse error exits with 0 before the test base can report it.
	if [ $status -ne 0 ] || grep -q -E "SCRIPT ERROR|Failed to load script" <<<"$output"; then
		echo "FAILED $test (exit $status)"
		failed=1
	fi
done
exit $failed
