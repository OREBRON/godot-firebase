#!/usr/bin/env python3
"""Build the desktop mock loader without Firebase SDKs or godot-cpp."""
import argparse
import os
from pathlib import Path
import platform
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    host = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["macos", "linux", "windows"], default=host)
    parser.add_argument("--arch", choices=["arm64", "x86_64"],
                        default="arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64")
    parser.add_argument("--cc", default=os.environ.get("CC", "clang" if host == "windows" else "cc"),
                        help='C compiler command, e.g. "clang" or "/path/to/zig cc"')
    args = parser.parse_args()
    if args.platform is None or (args.platform != "macos" and args.arch != "x86_64"):
        parser.error("Supported targets: macos arm64/x86_64, linux x86_64, windows x86_64")
    suffix = {"macos": "dylib", "linux": "so", "windows": "dll"}[args.platform]
    name = f"libgodot_firebase.{args.platform}.{args.arch}.{suffix}"
    output = ROOT / "addons/firebase/bin" / args.platform / name
    output.parent.mkdir(parents=True, exist_ok=True)
    compiler = shlex.split(args.cc, posix=os.name != "nt")
    if os.name == "nt":
        compiler = [token.strip('"') for token in compiler]
    if not compiler:
        parser.error("--cc must name a C compiler")
    flags = ["-std=c11", "-O2", "-g0", "-Wall", "-Wextra", "-Werror", "-ffreestanding",
             "-fno-stack-protector", "-fvisibility=hidden", "-nostdlib"]
    if Path(compiler[0]).stem == "zig":
        target_arch = "aarch64" if args.arch == "arm64" else args.arch
        target_os = {"macos": "macos", "linux": "linux-gnu", "windows": "windows-gnu"}[args.platform]
        flags += ["-target", f"{target_arch}-{target_os}"]
    if args.platform == "macos":
        flags += ["-dynamiclib", "-lSystem", "-arch", args.arch, "-mmacosx-version-min=11.0",
                  f"-Wl,-install_name,@rpath/{name}"]
    elif args.platform == "linux":
        flags += ["-shared", "-fPIC", "-Wl,--no-undefined", f"-Wl,-soname,{name}"]
    else:
        flags += ["-shared"]
        if Path(compiler[0]).stem != "zig":
            flags += ["--target=x86_64-pc-windows-msvc", "-fuse-ld=lld", "-Wl,/noentry"]
    subprocess.run([*compiler, *flags, str(ROOT / "src/desktop/godot_firebase_stub.c"),
                    "-o", str(output)], check=True)
    print(output.relative_to(ROOT))


if __name__ == "__main__":
    main()
