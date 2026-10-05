"""Split the verified CI monolith into alternative mobile installation ZIPs."""
import configparser
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import struct
import sys
import zipfile


SELECTED = "auth,firestore,functions,analytics,crashlytics,remote_config"
ROOT = "addons/firebase/"
BIN = ROOT + "bin/"


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def validate_mobile(archive, platform):
    names = set(archive.namelist())
    opposite = "android" if platform == "ios" else "ios"
    assert not any(n.startswith(BIN + opposite + "/") for n in names)
    assert archive.read(BIN + "modules.txt").decode().strip() == SELECTED
    config = configparser.ConfigParser()
    config.read_string(archive.read(ROOT + "plugin.cfg").decode())
    assert config["plugin"]["version"] == '"4.7.2"'
    for module in SELECTED.split(","):
        assert ROOT + f"{module}/firebase_{module}.gd" in names
        assert ROOT + f"{module}/firebase_{module}_mock.gd" in names
    assert not any(n.startswith(ROOT + m + "/") for m in ["database", "storage"] for n in names)
    # Real desktop stubs are required to open either ZIP in the editor.
    for host in ["linux", "windows", "macos"]:
        files = [n for n in names if n.startswith(BIN + host + "/")]
        assert files, host
        for name in files:
            assert not archive.read(name).startswith(b"version https://git-lfs.github.com/spec/v1")
    if platform == "android":
        for target in ["template_debug", "template_release"]:
            name = BIN + f"android/libgodot_firebase.android.{target}.so"
            header = archive.read(name)[:64]
            assert header[:6] == b"\x7fELF\x02\x01", name
            assert struct.unpack_from("<H", header, 18)[0] == 183, name
        aars = [n for n in names if n.startswith(BIN + "android/") and n.endswith(".aar")]
        assert len(aars) == 1, aars
    else:
        for target in ["template_debug", "template_release"]:
            prefix = BIN + f"ios/godot_firebase.ios.{target}.xcframework/"
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            libraries = info["AvailableLibraries"]
            assert len(libraries) == 2
            assert {lib.get("SupportedPlatformVariant", "device") for lib in libraries} == {"device", "simulator"}
            for library in libraries:
                assert library["SupportedPlatform"] == "ios"
                assert library["SupportedArchitectures"] == ["arm64"]
                name = prefix + library["LibraryIdentifier"] + "/" + library["LibraryPath"]
                header = archive.read(name)[:32]
                assert header[:4] == b"\xcf\xfa\xed\xfe", name
                assert struct.unpack_from("<I", header, 4)[0] == 0x0100000C, name
                assert struct.unpack_from("<I", header, 12)[0] == 6, name
        assert any(n.startswith(BIN + "ios/resources/") and n.endswith("PrivacyInfo.xcprivacy") for n in names)


source = Path(sys.argv[1]).resolve()
output_dir = source.parent.parent / "dist"
output_dir.mkdir(parents=True, exist_ok=True)
evidence = {"workflow_run": int(os.environ["GITHUB_RUN_ID"]), "source_commit": os.environ["GITHUB_SHA"], "monolith_sha256": digest(source), "modules": SELECTED, "packages": {}}
with zipfile.ZipFile(source) as original:
    assert original.testzip() is None
    entries = original.infolist()
    assert len({info.filename for info in entries}) == len(entries)
    for info in entries:
        path = PurePosixPath(info.filename)
        assert info.filename.startswith(ROOT) and ".." not in path.parts
        assert not stat.S_ISLNK(info.external_attr >> 16)
        assert not path.name.lower().startswith(("google-services", "googleservice-info"))
    for platform, opposite in [("ios", "android"), ("android", "ios")]:
        output = output_dir / f"godot-firebase-{platform}.zip"
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as destination:
            for info in entries:
                if not info.filename.startswith(BIN + opposite + "/"):
                    destination.writestr(copy.copy(info), original.read(info.filename))
        with zipfile.ZipFile(output) as packaged:
            assert packaged.testzip() is None
            validate_mobile(packaged, platform)
            for info in packaged.infolist():
                assert hashlib.sha256(packaged.read(info.filename)).digest() == hashlib.sha256(original.read(info.filename)).digest()
            evidence["packages"][platform] = {"name": output.name, "size": output.stat().st_size, "files": len(packaged.namelist()), "sha256": digest(output)}
        print(json.dumps(evidence["packages"][platform]))
(output_dir / "verification.json").write_text(json.dumps(evidence, indent=2) + "\n")
(output_dir / "SHA256SUMS-mobile.txt").write_text("".join(f"{v['sha256']}  {v['name']}\n" for v in evidence["packages"].values()))
