#!/usr/bin/env python3
"""Run editor import and every stock GDScript test on all desktop hosts."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, timeout):
    try:
        result = subprocess.run([os.environ.get("GODOT", "godot"), "--headless", *arguments],
                                cwd=ROOT, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout + result.stderr
    except (OSError, subprocess.TimeoutExpired) as error:
        return 1, str(error)


def main():
    status, output = run(["--editor", "--quit"], 120)
    if status or "ERROR:" in output or "SCRIPT ERROR" in output:
        print(output)
        print(f"FAILED editor import (exit {status})")
        return 1
    print("editor import: ok")
    failed = False
    for test in sorted((ROOT / "tests").glob("test_*.gd")):
        status, output = run(["--script", "res://tests/" + test.name], 60)
        success = test.name + ": ok"
        if status or "SCRIPT ERROR" in output or "Failed to load script" in output or success not in output:
            print(output)
            print(f"FAILED {test.name} (exit {status})")
            failed = True
        else:
            for line in output.splitlines():
                if line.startswith(("test_", "ERROR")):
                    print(line)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
