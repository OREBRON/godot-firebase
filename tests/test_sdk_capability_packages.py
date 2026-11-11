"""Development selection ZIP checks; these do not claim composable native artifacts."""
import configparser
import hashlib
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
MODULES = ["auth", "firestore", "storage", "database", "functions", "analytics", "remote_config", "crashlytics"]


def smoke_package(package_path, api_only=False):
    """Import a built selection ZIP into a fresh desktop game and start its APIs."""
    godot = os.environ.get("GODOT", "godot")
    with tempfile.TemporaryDirectory() as directory:
        game = Path(directory)
        with zipfile.ZipFile(package_path) as archive:
            archive.extractall(game)
        if api_only:
            for descriptor in game.rglob("*.gdextension"):
                descriptor.unlink()
        (game / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Firebase package smoke"\n')
        (game / "smoke.gd").write_text('''extends SceneTree
const API_ONLY := __API_ONLY__
func _initialize() -> void:
    _run.call_deferred()
func _run() -> void:
    if not API_ONLY and not GDExtensionManager.is_extension_loaded("res://addons/firebase/godot_firebase.gdextension"):
        push_error("packaged native GDExtension did not load")
        quit(1)
        return
    var firebase: Node = load("res://addons/firebase/core/firebase.gd").new()
    root.add_child(firebase)
    var selected := FileAccess.get_file_as_string("res://addons/firebase/bin/modules.txt").strip_edges().split(",")
    for module in firebase.MODULES:
        if selected.has(module):
            if firebase.get(module) == null or not firebase.is_available(module) or not firebase.is_mock(module):
                push_error("selected API failed desktop startup: " + module)
                quit(1)
                return
        elif firebase.get(module) != null:
            push_error("unselected API was installed: " + module)
            quit(1)
            return
    var calls := {"auth": ["sign_in_anonymously"], "firestore": ["set_doc", "smoke/doc", {"value": 1}], "database": ["set_value", "smoke", 1], "analytics": ["log_event", "smoke"], "remote_config": ["set_defaults", {"smoke": true}], "crashlytics": ["log_message", "smoke"]}
    for module in selected:
        if not calls.has(module):
            continue
        var arguments: Array = calls[module].duplicate()
        var method: String = arguments.pop_front()
        var task: RefCounted = firebase.get(module).callv(method, arguments)
        var result: Variant = await task.wait()
        if not result.ok:
            push_error("selected API request failed: " + module)
            quit(1)
            return
    print("packaged selection desktop smoke: ok (API-only)" if API_ONLY else "packaged selection desktop smoke: ok (native extension loaded)")
    quit(0)
'''.replace("__API_ONLY__", "true" if api_only else "false"))
        for args in [["--editor", "--quit"], ["--script", "res://smoke.gd"]]:
            result = subprocess.run([godot, "--headless", "--path", str(game), *args], capture_output=True, text=True, timeout=60)
            if result.returncode or "ERROR:" in result.stdout + result.stderr or "Failed to load script" in result.stdout + result.stderr:
                raise RuntimeError(result.stdout + result.stderr)
        if "packaged selection desktop smoke: ok" not in result.stdout:
            raise RuntimeError("Package smoke did not report completion: " + result.stdout + result.stderr)
        print(result.stdout.strip())


class DevelopmentPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        shutil.copy2(ROOT / "tools/package.sh", self.root / "tools/package.sh")
        self.addon = self.root / "addons/firebase"
        for module in MODULES:
            folder = self.addon / module
            folder.mkdir(parents=True)
            (folder / f"firebase_{module}.gd").write_text(f"# {module} API\n")
            (folder / f"firebase_{module}_mock.gd").write_text(f"# {module} mock\n")
        (self.addon / "core").mkdir()
        (self.addon / "core/firebase.gd").write_text("# shared Core\n")
        (self.addon / "bin").mkdir()
        (self.addon / "bin/native.so").write_bytes(b"fixture-selected-monolith")

    def package(self, modules):
        (self.addon / "bin/modules.txt").write_text(modules + "\n")
        result = subprocess.run(["bash", str(self.root / "tools/package.sh")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        path = Path(result.stdout.strip().splitlines()[-1])
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
        return path.name, names

    def test_three_new_single_payloads(self):
        for module in MODULES[5:]:
            with self.subTest(module=module):
                name, files = self.package(module)
                self.assertEqual(name, f"godot-firebase-{module.replace('_', '-')}.zip")
                for candidate in MODULES:
                    self.assertEqual(f"addons/firebase/{candidate}/firebase_{candidate}.gd" in files, candidate == module)
                self.assertIn("addons/firebase/core/firebase.gd", files)
                self.assertIn("addons/firebase/bin/native.so", files)

    def test_combination_contains_only_selected_apis(self):
        _, files = self.package("auth,database,remote_config")
        for module in MODULES:
            self.assertEqual(f"addons/firebase/{module}/firebase_{module}_mock.gd" in files, module in ["auth", "database", "remote_config"])

    def test_only_full_selection_is_named_godot_firebase(self):
        full, files = self.package(",".join(MODULES))
        self.assertEqual(full, "godot-firebase.zip")
        self.assertTrue(all(f"addons/firebase/{module}/firebase_{module}.gd" in files for module in MODULES))
        five, files = self.package(",".join(MODULES[:5]))
        self.assertEqual(five, "godot-firebase-auth-firestore-storage-database-functions.zip")
        self.assertNotIn("addons/firebase/analytics/firebase_analytics.gd", files)

    def test_game_config_excluded_including_custom_names(self):
        (self.addon / "google-services.dev.json").write_text("invalid but sensitive filename")
        (self.addon / "core/GoogleService-Info.plist").write_text("invalid but sensitive filename")
        (self.addon / "game.json").write_text(json.dumps({"project_info": {"project_id": "game"}, "client": []}))
        (self.addon / "custom.plist").write_bytes(plistlib.dumps({"GOOGLE_APP_ID": "1:game:ios:id", "BUNDLE_ID": "test.game"}, fmt=plistlib.FMT_BINARY))
        (self.addon / "bin/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "native.resource"}))
        _, files = self.package("crashlytics")
        for relative in ["google-services.dev.json", "core/GoogleService-Info.plist", "game.json", "custom.plist"]:
            self.assertNotIn("addons/firebase/" + relative, files)
        self.assertIn("addons/firebase/bin/Info.plist", files)

    def test_license_and_notice_files_are_shipped(self):
        notices = ["LICENSE.md", "bin/NOTICE", "auth/THIRD_PARTY_NOTICES.txt"]
        for relative in notices:
            (self.addon / relative).write_text("notice text\n")
        _, files = self.package("auth")
        for relative in notices:
            self.assertIn("addons/firebase/" + relative, files)

    def test_files_outside_allowlist_fail_the_package(self):
        (self.addon / "bin/modules.txt").write_text("auth\n")
        bom_config = b"\xef\xbb\xbf" + json.dumps({"project_info": {}, "client": []}).encode()
        for relative, content in [("google-services.json.bak", b"{}"), ("core/game.json", bom_config),
                                  ("release.jks", b"key"), ("bin/upload.keystore", b"key"), ("core/cert.p12", b"key"),
                                  (".env", b"TOKEN=x"), ("bin/game.mobileprovision", b"profile"), ("auth/notes.txt", b"x"),
                                  ("LICENSE.bak", b"x")]:
            with self.subTest(file=relative):
                path = self.addon / relative
                path.write_bytes(content)
                result = subprocess.run(["bash", str(self.root / "tools/package.sh")], capture_output=True, text=True)
                path.unlink()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(relative, result.stderr)
                self.assertFalse(list((self.root / "build/dist").glob("*.zip")))

    def test_invalid_selection_rejected(self):
        for selection in ["", "auth,auth", "auth,unknown", "../core", "auth,,database"]:
            with self.subTest(selection=selection):
                (self.addon / "bin/modules.txt").write_text(selection)
                result = subprocess.run(["bash", str(self.root / "tools/package.sh")], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)


class SymbolIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def verify(self, platform, binary, symbols, *options):
        return subprocess.run(["python3", str(ROOT / "tools/verify_crashlytics_symbols.py"), platform,
            "--binary", str(binary), "--symbols", str(symbols), *map(str, options)], capture_output=True, text=True, cwd=self.root)

    @unittest.skipUnless(shutil.which("xcrun"), "Xcode required for real Mach-O/dSYM fixtures")
    def test_macho_uuid_and_nonempty_dwarf(self):
        source = self.root / "fixture.cpp"
        for name, number in [("one", 7), ("two", 8)]:
            source.write_text('extern "C" int symbol_fixture() { return %d; }\n' % number)
            obj, binary, dsym = [self.root / (name + suffix) for suffix in [".o", ".dylib", ".dSYM"]]
            subprocess.run(["xcrun", "clang++", "-g", "-c", str(source), "-o", str(obj)], check=True, capture_output=True)
            subprocess.run(["xcrun", "clang++", "-dynamiclib", str(obj), "-o", str(binary)], check=True, capture_output=True)
            subprocess.run(["xcrun", "dsymutil", str(binary), "-o", str(dsym)], check=True, capture_output=True)
        result = self.verify("ios", self.root / "one.dylib", self.root / "one.dSYM")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads(result.stdout)
        self.assertEqual(len(manifest["binary"]["sha256"]), 64)
        # Published identity.json files must not leak the builder's absolute paths.
        self.assertEqual(manifest["binary"]["path"], "one.dylib")
        self.assertTrue(all(record["path"].startswith("one.dSYM/") for record in manifest["symbols"]))
        result = self.verify("ios", self.root / "one.dylib", self.root / "two.dSYM")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("do not match", result.stderr)
        (self.root / "one.o").unlink()
        subprocess.run(["xcrun", "dsymutil", str(self.root / "one.dylib"), "-o", str(self.root / "empty.dSYM")], check=True, capture_output=True)
        result = self.verify("ios", self.root / "one.dylib", self.root / "empty.dSYM")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no DWARF", result.stderr)

    def android_ndk(self):
        sdk = os.environ.get("ANDROID_HOME", os.environ.get("ANDROID_SDK_ROOT", ""))
        host = "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64"
        ndk = Path(sdk) / "ndk" / os.environ.get("NDK_VERSION", "28.1.13356709") / "toolchains/llvm/prebuilt" / host / "bin"
        if not (ndk / "aarch64-linux-android24-clang++").is_file():
            self.skipTest("Set ANDROID_HOME and NDK_VERSION for real Android ELF fixtures")
        return ndk

    def test_android_build_id_and_unstripped_symbols(self):
        ndk = self.android_ndk()
        compiler = ndk / "aarch64-linux-android24-clang++"
        source = self.root / "fixture.cpp"
        for name, number in [("one", 7), ("two", 8)]:
            source.write_text('extern "C" int symbol_fixture() { return %d; }\n' % number)
            subprocess.run([str(compiler), "-g", "-shared", "-Wl,--build-id=sha1", str(source), "-o", str(self.root / (name + ".so"))], check=True, capture_output=True)
        binary = self.root / "exported.so"
        subprocess.run([str(ndk / "llvm-strip"), "--strip-all", str(self.root / "one.so"), "-o", str(binary)], check=True, capture_output=True)
        options = ["--readelf", ndk / "llvm-readelf"]
        result = self.verify("android", binary, self.root / "one.so", *options)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads(result.stdout)
        self.assertEqual([manifest["binary"]["path"], manifest["symbols"][0]["path"]], ["exported.so", "one.so"])
        result = self.verify("android", binary, self.root / "two.so", *options)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("do not match", result.stderr)
        result = self.verify("android", binary, binary, *options)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DWARF", result.stderr)

    def test_crashlytics_build_ships_stripped_android_library(self):
        ndk = self.android_ndk()
        (self.root / "tools").mkdir()
        for name in ["build.sh", "versions.env", "verify_crashlytics_symbols.py"]:
            shutil.copy2(ROOT / "tools" / name, self.root / "tools" / name)
        (self.root / "tools/build_android_aar.sh").write_text("")
        # Stands in for SCons: links the requested target with DWARF and a build ID.
        scons = self.root / "scons.sh"
        scons.write_text(f'''for arg; do [[ $arg != target=* ]] || target=${{arg#target=}}; done
mkdir -p build/android
echo 'extern "C" int fixture() {{ return 7; }}' > build/fixture.cpp
"{ndk}/aarch64-linux-android24-clang++" -g -shared -Wl,--build-id=sha1 build/fixture.cpp -o "build/android/libgodot_firebase.android.$target.so"
''')
        result = subprocess.run(["bash", "tools/build.sh", "--platforms", "android", "--modules", "crashlytics"],
            cwd=self.root, env={**os.environ, "SCONS": f"bash {scons}"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for target in ["template_debug", "template_release"]:
            stem = f"libgodot_firebase.android.{target}.so"
            shipped = self.root / "addons/firebase/bin/android" / stem
            symbols = self.root / "build/symbols/crashlytics/android" / target / "arm64-v8a"
            sections = [subprocess.check_output([str(ndk / "llvm-readelf"), "--sections", str(path)], text=True) for path in [shipped, symbols / stem]]
            self.assertNotIn(".debug_info", sections[0])
            self.assertIn(".debug_info", sections[1])
            identity = json.loads((symbols / "identity.json").read_text())
            self.assertEqual(identity["binary"]["sha256"], hashlib.sha256(shipped.read_bytes()).hexdigest())


class NativePackageImportTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("GODOT") or shutil.which("godot"), "Godot required for package loader regression")
    def test_corrupt_native_is_rejected_by_default_smoke(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            shutil.copy2(ROOT / "tools/package.sh", root / "tools/package.sh")
            shutil.copytree(ROOT / "addons/firebase", root / "addons/firebase", ignore=shutil.ignore_patterns("bin"))
            descriptor = configparser.ConfigParser()
            descriptor.read(root / "addons/firebase/godot_firebase.gdextension")
            for features, library in descriptor["libraries"].items():
                if features.split(".")[0] in {"macos", "linux", "windows"}:
                    native = root / library.strip('"').removeprefix("res://")
                    native.parent.mkdir(parents=True, exist_ok=True)
                    native.write_bytes(b"invalid desktop native library")
            (root / "addons/firebase/bin/modules.txt").write_text("analytics\n")
            package = subprocess.check_output(["bash", str(root / "tools/package.sh")], text=True).strip()
            with self.assertRaises(RuntimeError):
                smoke_package(package)
            smoke_package(package, api_only=True)


if __name__ == "__main__":
    if len(sys.argv) in (3, 4) and sys.argv[1] == "--smoke-package" and (len(sys.argv) == 3 or sys.argv[3] == "--api-only"):
        smoke_package(sys.argv[2], api_only=len(sys.argv) == 4)
    else:
        unittest.main()
