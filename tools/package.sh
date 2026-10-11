#!/usr/bin/env bash
# Package the current selected monolithic build. These ZIPs are not composable.
# modules.txt describes selection; it does not prove binary freshness/provenance.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import tempfile
import zipfile


def game_config(path):
    name = path.name.lower()
    if (name.startswith("google-services") and name.endswith(".json")) or (name.startswith("googleservice-info") and name.endswith(".plist")):
        return True
    try:
        if path.suffix.lower() == ".json":
            data = json.loads(path.read_text(encoding="utf-8"))
            return isinstance(data, dict) and "project_info" in data and "client" in data
        if path.suffix.lower() == ".plist":
            with path.open("rb") as source:
                data = plistlib.load(source)
            return isinstance(data, dict) and "GOOGLE_APP_ID" in data
    except (ValueError, UnicodeError, plistlib.InvalidFileException):
        pass
    return False


def package():
    addon = Path("addons/firebase")
    modules = (addon / "bin/modules.txt").read_text(encoding="utf-8").strip().split(",")
    available = {p.name for p in addon.iterdir() if p.is_dir() and (p / ("firebase_" + p.name + ".gd")).is_file()}
    if not modules or len(set(modules)) != len(modules) or any(not re.fullmatch(r"[a-z][a-z0-9_]*", module) or module not in available for module in modules):
        raise ValueError("modules.txt must select distinct installed product names separated by commas")
    selected = set(modules)
    # Only the full selection owns the plain name; every other selection names its products.
    if selected == available:
        name = "godot-firebase.zip"
    else:
        name = "godot-firebase-" + "-".join(module.replace("_", "-") for module in modules) + ".zip"
    output_dir = Path("build/dist")
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / name
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output_dir, suffix=".zip", delete=False) as staged:
            temporary = Path(staged.name)
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(addon.rglob("*")):
                relative = path.relative_to(addon)
                if relative.parts[0] in available - selected or path.name == ".DS_Store":
                    continue
                if path.is_symlink():
                    raise ValueError(f"Package input must not contain symlinks: {path}")
                if path.is_file() and not game_config(path):
                    archive.write(path, path.as_posix())
        os.replace(temporary, output)
        print(output.resolve())
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


try:
    package()
except (OSError, ValueError) as error:
    print(f"Package failed: {error}", file=sys.stderr)
    sys.exit(1)
PY
