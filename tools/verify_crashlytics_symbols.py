#!/usr/bin/env python3
"""Verify one exported native binary against its symbols without uploading anything."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def run(tool, *args):
    result = subprocess.run([tool, *map(str, args)], check=True, capture_output=True, text=True)
    return result.stdout


def file_record(path):
    path = Path(path).resolve(strict=True)
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Expected a nonempty file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    # Relative to the working directory (repo root in build.sh): published manifests must not leak local paths.
    return {"path": os.path.relpath(path), "sha256": digest.hexdigest()}


def elf_identity(tool, binary):
    notes = run(tool, "--notes", binary)
    ids = re.findall(r"Build ID:\s*([0-9a-fA-F]+)", notes)
    machine = re.search(r"Machine:\s*(.+)", run(tool, "--file-header", binary))
    if len(ids) != 1 or machine is None:
        raise ValueError(f"Expected one GNU build ID and ELF machine: {binary}")
    return {"build_id": ids[0].lower(), "machine": machine.group(1).strip()}


def macho_identity(tool, binary):
    pairs = re.findall(r"UUID:\s*([0-9A-Fa-f-]+)\s*\(([^)]+)\)", run(tool, "--uuid", binary))
    if not pairs or len({arch for _, arch in pairs}) != len(pairs):
        raise ValueError(f"Expected one UUID per Mach-O architecture: {binary}")
    return {arch: uuid.upper() for uuid, arch in pairs}


def verify(args):
    binary = Path(args.binary).resolve(strict=True)
    symbols = Path(args.symbols).resolve(strict=True)
    manifest = {"schema_version": 1, "platform": args.platform, "binary": file_record(binary)}
    if args.platform == "android":
        identity = elf_identity(args.readelf, binary)
        if identity != elf_identity(args.readelf, symbols):
            raise ValueError("Exported ELF and symbol ELF build ID/architecture do not match")
        sections = run(args.readelf, "--sections", symbols)
        if not re.search(r"\.(?:z?debug_info)\b", sections) or ".symtab" not in sections:
            raise ValueError("Symbol ELF must retain DWARF debug info and its full symbol table")
        manifest.update(identity=identity, symbols=[file_record(symbols)])
    else:
        dwarf_dir = symbols / "Contents" / "Resources" / "DWARF"
        dwarf_files = sorted(path for path in dwarf_dir.iterdir() if path.is_file())
        if not dwarf_files:
            raise ValueError("Expected a dSYM bundle containing DWARF files")
        identity = macho_identity(args.dwarfdump, binary)
        supplied = macho_identity(args.dwarfdump, symbols)
        if any(supplied.get(arch) != uuid for arch, uuid in identity.items()):
            raise ValueError("Exported Mach-O and dSYM UUIDs do not match for every exported architecture")
        for arch in identity:
            info = run(args.dwarfdump, "--debug-info", "--recurse-depth=0", "--arch=" + arch, symbols)
            if "DW_TAG_compile_unit" not in info:
                raise ValueError(f"dSYM has no DWARF compilation units for exported architecture {arch}")
        manifest.update(identity=identity, symbols=[file_record(path) for path in dwarf_files])
    if args.mapping:
        if args.platform != "android":
            raise ValueError("R8 mapping only applies to Android")
        # Records provenance only. ELF identity cannot prove mapping-to-APK correspondence.
        manifest["r8_mapping"] = file_record(args.mapping)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=["android", "ios"])
    parser.add_argument("--binary", required=True)
    parser.add_argument("--symbols", required=True, help="Unstripped .so or matching .dSYM bundle")
    parser.add_argument("--readelf", default="llvm-readelf")
    parser.add_argument("--dwarfdump", default="dwarfdump")
    parser.add_argument("--mapping", help="Optional R8 mapping.txt from this same game export")
    parser.add_argument("--output", help="Write verified identity/SHA-256 manifest to this path")
    args = parser.parse_args()
    try:
        manifest = verify(args)
        encoded = json.dumps(manifest, indent=2) + "\n"
        if args.output:
            Path(args.output).write_text(encoded, encoding="utf-8")
        print(encoded, end="")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Crashlytics symbol verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
