"""Packaging/signature failure gates. Fake Apple tools test orchestration on Linux.

These fixtures are not evidence of an Apple signature or App Store acceptance.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TEAM = "ABCDE12345"
IDENTITY = f"Apple Distribution: SDK Fixture ({TEAM})"

APPLE_TOOL = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
args = sys.argv[1:]
if pathlib.Path(sys.argv[0]).name == "security":
    if not os.environ.get("NO_IDENTITY"):
        print('  1) ' + 'A' * 40 + ' "' + os.environ["IOS_SIGNING_IDENTITY"] + '"')
    sys.exit(0)
path = pathlib.Path(args[-1])
record = path / ".fixture-signature"
def manifest():
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob("*") if p.is_file() and p != record}
if "--sign" in args:
    record.write_text(json.dumps({"files": manifest(), "team": os.environ.get("FAKE_CERT_TEAM", "ABCDE12345")}))
elif "--verify" in args:
    if not record.is_file():
        sys.exit("code object is not signed at all")
    data = json.loads(record.read_text())
    if data["files"] != manifest():
        sys.exit("sealed resource is missing or invalid")
    if os.environ.get("FAIL_EXTRACTED_VERIFY") and "ios-verify-" in str(path):
        sys.exit("extracted signature invalid")
    requirement = args[args.index("-R") + 1]
    if '"' + data["team"] + '"' not in requirement or "anchor apple generic" not in requirement:
        sys.exit("code failed to satisfy specified code requirement(s)")
else:
    data = json.loads(record.read_text())
    authority = os.environ.get("FAKE_AUTHORITY", "Apple Distribution: SDK Fixture (" + data["team"] + ")")
    if path.suffix == ".app":
        authority = os.environ.get("FAKE_APP_AUTHORITY", authority)
    print("Authority=" + authority, file=sys.stderr)
    print("TeamIdentifier=" + data["team"], file=sys.stderr)
    if not os.environ.get("NO_TIMESTAMP"):
        print("Timestamp=Oct 15, 2026 at 12:00:00", file=sys.stderr)
    if os.environ.get("ADHOC"):
        print("Signature=adhoc", file=sys.stderr)
'''


class IOSSigningTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ios-signing-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "tools").mkdir()
        for name in ["package.sh", "ios_signing.py"]:
            source = ROOT / "tools" / name
            if source.exists():
                shutil.copy2(source, self.root / "tools" / name)
        self.addon = self.root / "addons/firebase"
        (self.addon / "auth").mkdir(parents=True)
        (self.addon / "auth/firebase_auth.gd").write_text("# fixture\n")
        (self.addon / "bin/ios").mkdir(parents=True)
        (self.addon / "bin/modules.txt").write_text("auth\n")
        self.frameworks = []
        for target in ["template_debug", "template_release"]:
            path = self.addon / f"bin/ios/godot_firebase.ios.{target}.xcframework"
            path.mkdir()
            libraries = []
            for identifier in ["ios-arm64", "ios-arm64-simulator"]:
                framework = path / identifier / "godot_firebase.framework"
                framework.mkdir(parents=True)
                (framework / "godot_firebase").write_bytes(b"fixture binary")
                (framework / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "godot_firebase"}))
                library = {"LibraryIdentifier": identifier, "LibraryPath": framework.name,
                           "SupportedPlatform": "ios"}
                if identifier.endswith("simulator"):
                    library["SupportedPlatformVariant"] = "simulator"
                libraries.append(library)
            (path / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))
            self.frameworks.append(path)
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        for name in ["codesign", "security"]:
            tool = fake_bin / name
            tool.write_text(APPLE_TOOL)
            tool.chmod(0o755)
        self.env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                    "IOS_SIGNING_IDENTITY": IDENTITY, "IOS_SIGNING_TEAM_ID": TEAM}
        self.env.pop("IOS_SIGNING_KEYCHAIN", None)

    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(self.root / "tools/ios_signing.py"), *map(str, args)],
                              env=self.env, capture_output=True, text=True)

    def package(self, *args):
        return subprocess.run(["bash", str(self.root / "tools/package.sh"), *args],
                              env=self.env, capture_output=True, text=True)

    def test_signed_package_filters_before_signing_and_verifies_zip(self):
        (self.frameworks[0] / "GoogleService-Info.plist").write_text("game secret")
        result = self.package("--sign-ios")
        self.assertEqual(result.returncode, 0, result.stderr)
        output = Path(result.stdout.strip())
        with zipfile.ZipFile(output) as archive:
            self.assertFalse(any("GoogleService-Info.plist" in name for name in archive.namelist()))
            # Two containers and four framework slices are signed inside-out.
            self.assertEqual(sum(name.endswith(".fixture-signature") for name in archive.namelist()), 6)
        # The original build is untouched; only the selected, filtered stage is signed.
        self.assertFalse((self.frameworks[0] / ".fixture-signature").exists())
        checked = self.run_tool("verify-package", output, "--team-id", TEAM)
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_unsigned_local_package_is_still_available(self):
        self.env.pop("IOS_SIGNING_IDENTITY")
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_identity_cannot_publish_a_package(self):
        self.env.pop("IOS_SIGNING_IDENTITY")
        result = self.package("--sign-ios")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("IOS_SIGNING_IDENTITY", result.stderr)
        self.assertFalse(list((self.root / "build/dist").glob("*.zip")))

    def test_missing_private_key_and_wrong_certificate_are_rejected(self):
        for changes in [{"NO_IDENTITY": "1"}, {"IOS_SIGNING_IDENTITY": "-"},
                        {"IOS_SIGNING_IDENTITY": f"Developer ID Application: Fixture ({TEAM})"}]:
            with self.subTest(changes=changes):
                previous = self.env.copy()
                self.env.update(changes)
                result = self.run_tool("check-identity")
                self.assertNotEqual(result.returncode, 0)
                self.env = previous

    def test_development_member_id_need_not_equal_team_id(self):
        self.env["IOS_SIGNING_IDENTITY"] = "Apple Development: Developer (MEMBER1234)"
        self.env["FAKE_AUTHORITY"] = self.env["IOS_SIGNING_IDENTITY"]
        result = self.package("--sign-ios")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_release_variant_is_rejected(self):
        shutil.rmtree(self.frameworks[1])
        result = self.package("--sign-ios")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("template_release", result.stderr)

    def test_dylib_layout_is_rejected_before_signing(self):
        plist = self.frameworks[0] / "Info.plist"
        data = plistlib.loads(plist.read_bytes())
        data["AvailableLibraries"][0]["LibraryPath"] = "library.dylib"
        plist.write_bytes(plistlib.dumps(data))
        result = self.package("--sign-ios")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Rebuild", result.stderr)

    def test_bad_signatures_cannot_replace_existing_package(self):
        output = self.root / "build/dist/godot-firebase.zip"
        output.parent.mkdir(parents=True)
        output.write_bytes(b"previous verified release")
        for changes in [{"FAIL_EXTRACTED_VERIFY": "1"}, {"NO_TIMESTAMP": "1"},
                        {"ADHOC": "1"}, {"FAKE_AUTHORITY": "Untrusted: Fixture"},
                        {"IOS_SIGNING_TEAM_ID": "WRONG12345"}]:
            with self.subTest(changes=changes):
                previous = self.env.copy()
                self.env.update(changes)
                result = self.package("--sign-ios")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_bytes(), b"previous verified release")
                self.assertEqual(list(output.parent.glob("*.zip")), [output])
                self.env = previous

    def test_unsigned_and_tampered_zip_are_rejected(self):
        unsigned = self.package()
        self.assertEqual(unsigned.returncode, 0, unsigned.stderr)
        self.assertNotEqual(self.run_tool("verify-package", unsigned.stdout.strip(), "--team-id", TEAM).returncode, 0)
        signed = self.package("--sign-ios")
        self.assertEqual(signed.returncode, 0, signed.stderr)
        path = Path(signed.stdout.strip())
        with zipfile.ZipFile(path) as archive:
            entries = {entry.filename: archive.read(entry) for entry in archive.infolist()}
        binary = next(name for name in entries if name.endswith(".framework/godot_firebase"))
        entries[binary] = b"modified after signing"
        with zipfile.ZipFile(path, "w") as archive:
            for name, content in entries.items():
                archive.writestr(name, content)
        result = self.run_tool("verify-package", path, "--team-id", TEAM)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sealed resource", result.stderr)

    def make_ipa(self, framework_team=TEAM, include_firebase=True, unsigned=False):
        root = self.root / "export"
        app = root / "Payload/Game.app"
        app.mkdir(parents=True, exist_ok=True)
        (app / "Game").write_bytes(b"fixture game")
        framework = app / "Frameworks/libgodot_firebase.ios.template_release.framework"
        if include_firebase:
            framework.mkdir(parents=True)
            (framework / "libgodot_firebase.ios.template_release").write_bytes(b"fixture binary")
            subprocess.run(["codesign", "--sign", IDENTITY, str(framework)],
                           env={**self.env, "FAKE_CERT_TEAM": framework_team}, check=True)
            if unsigned:
                (framework / ".fixture-signature").unlink()
        subprocess.run(["codesign", "--sign", IDENTITY, str(app)], env=self.env, check=True)
        output = self.root / "Game.ipa"
        with zipfile.ZipFile(output, "w") as archive:
            for path in root.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(root))
        return output

    def test_final_ipa_accepts_game_team_independent_of_sdk_team(self):
        ipa = self.make_ipa()
        self.env["IOS_SIGNING_TEAM_ID"] = "SDKTEAM123"
        result = self.run_tool("verify-ipa", ipa, "--team-id", TEAM)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_distribution_gate_accepts_distribution_ipa(self):
        result = self.run_tool("verify-ipa", self.make_ipa(), "--team-id", TEAM, "--distribution")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_distribution_gate_rejects_development_signature(self):
        ipa = self.make_ipa()
        self.env["FAKE_AUTHORITY"] = "Apple Development: Developer (MEMBER1234)"
        # Development signatures remain valid for local device verification.
        result = self.run_tool("verify-ipa", ipa, "--team-id", TEAM)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_tool("verify-ipa", ipa, "--team-id", TEAM, "--distribution")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected an Apple Distribution signature", result.stderr)

    def test_distribution_gate_checks_app_after_frameworks(self):
        ipa = self.make_ipa()
        self.env["FAKE_APP_AUTHORITY"] = "Apple Development: Developer (MEMBER1234)"
        result = self.run_tool("verify-ipa", ipa, "--team-id", TEAM, "--distribution")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected an Apple Distribution signature", result.stderr)
        self.assertIn("Game.app", result.stderr)

    def test_ipa_rejects_unsigned_framework(self):
        result = self.run_tool("verify-ipa", self.make_ipa(unsigned=True), "--team-id", TEAM)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not signed", result.stderr)

    def test_ipa_rejects_framework_with_different_team(self):
        result = self.run_tool("verify-ipa", self.make_ipa(framework_team="WRONG12345"), "--team-id", TEAM)
        self.assertNotEqual(result.returncode, 0)

    def test_ipa_without_firebase_is_not_a_success(self):
        result = self.run_tool("verify-ipa", self.make_ipa(include_firebase=False), "--team-id", TEAM)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Firebase", result.stderr)

    def test_unsafe_archive_is_rejected(self):
        for names in [["../outside"], ["Info.plist", "info.plist"]]:
            with self.subTest(names=names):
                archive = self.root / "unsafe.zip"
                with zipfile.ZipFile(archive, "w") as output:
                    for name in names:
                        output.writestr(name, "bad")
                result = self.run_tool("verify-package", archive, "--team-id", TEAM)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unsafe", result.stderr)


class IOSFrameworkBuildTests(unittest.TestCase):
    def test_framework_layout_precedes_xcframework_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            shim = '''#!/usr/bin/env python3
import pathlib, plistlib, shutil, sys
args = sys.argv[1:]
if pathlib.Path(sys.argv[0]).name == "xcrun":
    binary = pathlib.Path(args[-1])
    binary.write_bytes(binary.read_bytes() + args[2].encode())
else:
    output = pathlib.Path(args[args.index("-output") + 1])
    libraries = []
    for i, value in enumerate(args):
        if value != "-framework": continue
        framework = pathlib.Path(args[i + 1])
        plist = plistlib.loads((framework / "Info.plist").read_bytes())
        binary = framework / plist["CFBundleExecutable"]
        assert binary.is_file()
        assert b"@rpath/" in binary.read_bytes()
        identifier = "ios-arm64" + ("-simulator" if plist["DTPlatformName"] == "iphonesimulator" else "")
        shutil.copytree(framework, output / identifier / framework.name)
        library = {"LibraryIdentifier": identifier, "LibraryPath": framework.name, "SupportedPlatform": "ios"}
        if identifier.endswith("simulator"): library["SupportedPlatformVariant"] = "simulator"
        libraries.append(library)
    assert len(libraries) == 2
    (output / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))
'''
            for name in ["xcrun", "xcodebuild"]:
                tool = fake_bin / name
                tool.write_text(shim)
                tool.chmod(0o755)
            stem = "libgodot_firebase.ios.template_release"
            for suffix in ["", ".simulator"]:
                (root / f"{stem}{suffix}.dylib").write_bytes(b"original binary")
            output = root / "output.xcframework"
            result = subprocess.run([sys.executable, str(ROOT / "tools/build_ios_xcframework.py"),
                                     "--target", "template_release", "--build-dir", str(root),
                                     "--output", str(output)], capture_output=True, text=True,
                                    env={**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]})
            self.assertEqual(result.returncode, 0, result.stderr)
            plist = plistlib.loads((output / "Info.plist").read_bytes())
            for library in plist["AvailableLibraries"]:
                framework = output / library["LibraryIdentifier"] / library["LibraryPath"]
                self.assertEqual(framework.name, stem + ".framework")
                metadata = plistlib.loads((framework / "Info.plist").read_bytes())
                self.assertEqual(metadata["CFBundleExecutable"], stem)
                self.assertEqual(metadata["CFBundlePackageType"], "FMWK")
                self.assertEqual(metadata["MinimumOSVersion"], "15.0")
                self.assertNotIn("_", metadata["CFBundleIdentifier"])
                self.assertIn(f"@rpath/{stem}.framework/{stem}".encode(), (framework / stem).read_bytes())
            self.assertEqual((root / f"{stem}.dylib").read_bytes(), b"original binary")


@unittest.skipUnless(sys.platform == "darwin" and os.environ.get("IOS_SIGNING_IDENTITY"),
                     "macOS and Apple signing identity required for real signed XCFramework fixture")
class AppleSigningIntegrationTests(unittest.TestCase):
    def test_real_signed_zip_and_tamper_detection(self):
        with tempfile.TemporaryDirectory(prefix="apple-signing-") as temporary:
            root = Path(temporary)
            (root / "tools").mkdir()
            for name in ["package.sh", "ios_signing.py"]:
                shutil.copy2(ROOT / "tools" / name, root / "tools" / name)
            addon = root / "addons/firebase"
            (addon / "auth").mkdir(parents=True)
            (addon / "auth/firebase_auth.gd").write_text("# fixture\n")
            ios = addon / "bin/ios"
            ios.mkdir(parents=True)
            (addon / "bin/modules.txt").write_text("auth\n")
            source = root / "fixture.c"
            source.write_text("int firebase_signing_fixture(void) { return 42; }\n")
            build_dir = root / "build/ios"
            build_dir.mkdir(parents=True)
            for sdk, minimum in [("iphoneos", "-miphoneos-version-min=15.0"),
                                 ("iphonesimulator", "-mios-simulator-version-min=15.0")]:
                suffix = ".simulator" if sdk == "iphonesimulator" else ""
                library = build_dir / f"libgodot_firebase.ios.template_debug{suffix}.dylib"
                subprocess.run(["xcrun", "--sdk", sdk, "clang", "-dynamiclib", "-arch", "arm64",
                                "-Wl,-headerpad_max_install_names", minimum, str(source), "-o", str(library)],
                               check=True, capture_output=True)
                shutil.copy2(library, build_dir / f"libgodot_firebase.ios.template_release{suffix}.dylib")
            for target in ["template_debug", "template_release"]:
                subprocess.run([sys.executable, str(ROOT / "tools/build_ios_xcframework.py"),
                                "--target", target, "--build-dir", str(build_dir), "--output",
                                str(ios / f"godot_firebase.ios.{target}.xcframework")], check=True, capture_output=True)
            result = subprocess.run(["bash", str(root / "tools/package.sh"), "--sign-ios"],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            path = Path(result.stdout.strip())
            with zipfile.ZipFile(path) as archive:
                entries = {entry.filename: (entry, archive.read(entry)) for entry in archive.infolist()}
            binary = next(name for name in entries if name.endswith(".framework/libgodot_firebase.ios.template_release"))
            entry, content = entries[binary]
            entries[binary] = (entry, content + b"tampered")
            with zipfile.ZipFile(path, "w") as archive:
                for entry, content in entries.values():
                    archive.writestr(entry, content)
            result = subprocess.run([sys.executable, str(ROOT / "tools/ios_signing.py"), "verify-package",
                                     str(path), "--team-id", os.environ["IOS_SIGNING_TEAM_ID"]],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("codesign failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
