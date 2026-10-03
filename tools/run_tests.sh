#!/usr/bin/env bash
# Compatibility entry point; Python also supports Windows without Perl/alarm.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/run_tests.py
