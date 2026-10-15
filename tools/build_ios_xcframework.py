#!/usr/bin/env python3
"""Wrap iOS dylibs before signing so Godot can copy the XCFramework unchanged."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def build_xcframework(build_dir, target, output):
    stem = f"libgodot_firebase.ios.{target}"
    build_dir = build_dir.resolve()
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ios-framework-", dir=build_dir) as temporary:
        stage = Path(temporary)
        frameworks = []
        for sdk, suffix in [("iphoneos", ""), ("iphonesimulator", ".simulator")]:
            framework = stage / sdk / f"{stem}.framework"
            framework.mkdir(parents=True)
            binary = framework / stem
            shutil.copy2(build_dir / f"{stem}{suffix}.dylib", binary)
            subprocess.run(["xcrun", "install_name_tool", "-id", f"@rpath/{framework.name}/{stem}",
                            str(binary)], check=True)
            metadata = {
                "CFBundleExecutable": stem,
                "CFBundleIdentifier": "org.godotfirebase." + stem.replace("_", "-"),
                "CFBundleName": stem,
                "CFBundlePackageType": "FMWK",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
                "DTPlatformName": sdk,
                "CFBundleSupportedPlatforms": ["iPhoneOS" if sdk == "iphoneos" else "iPhoneSimulator"],
                "MinimumOSVersion": "15.0",
            }
            (framework / "Info.plist").write_bytes(plistlib.dumps(metadata))
            frameworks.extend(["-framework", str(framework)])
        staged_output = stage / output.name
        subprocess.run(["xcodebuild", "-create-xcframework", *frameworks, "-output", str(staged_output)], check=True)
        if output.exists():
            shutil.rmtree(output)
        shutil.move(str(staged_output), output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, choices=["template_debug", "template_release"])
    parser.add_argument("--build-dir", type=Path, default=Path("build/ios"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build_xcframework(args.build_dir, args.target, args.output)
