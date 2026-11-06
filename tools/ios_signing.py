#!/usr/bin/env python3
"""Sign staged iOS SDKs and verify delivered ZIPs or final Godot IPAs on macOS."""
import argparse
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"{args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout + result.stderr


def team_id(value):
    if not re.fullmatch(r"[A-Z0-9]{10}", value):
        raise ValueError("Set a 10-character Apple team ID (IOS_SIGNING_TEAM_ID or --team-id)")
    return value


def signing_identity():
    identity = os.environ.get("IOS_SIGNING_IDENTITY", "").strip()
    if not identity or identity == "-":
        raise ValueError("Set IOS_SIGNING_IDENTITY to an Apple Distribution/Development certificate name or SHA-1")
    team = team_id(os.environ.get("IOS_SIGNING_TEAM_ID", ""))
    keychain = os.environ.get("IOS_SIGNING_KEYCHAIN", "")
    output = run("security", "find-identity", "-v", "-p", "codesigning", *([keychain] if keychain else []))
    matches = []
    for fingerprint, name in re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"\s*$', output, re.MULTILINE):
        # Development CNs contain a member ID, which can differ from the team.
        # verify_signature checks the certificate's actual subject.OU after signing.
        if (identity == name or identity.upper() == fingerprint.upper()) and re.fullmatch(
                r"Apple (Distribution|Development): .+", name):
            matches.append(fingerprint)
    if len(matches) != 1:
        raise ValueError("IOS_SIGNING_IDENTITY must select exactly one valid Apple Distribution/Development "
                         "identity, with its private key in the runner's Keychain")
    return matches[0], team, keychain


def verify_signature(path, team, timestamp=False, deep=False, distribution=False):
    # A valid ad-hoc or self-signed signature is insufficient. Check Apple trust
    # and the expected team cryptographically, then constrain the certificate kind.
    requirement = f'=anchor apple generic and certificate leaf[subject.OU] = "{team_id(team)}"'
    print(run("codesign", "--verify", "--strict", "--verbose=2", *(["--deep"] if deep else []),
              "-R", requirement, path), file=sys.stderr, end="")
    details = run("codesign", "-dvv", path)
    print(details, file=sys.stderr, end="")
    if "Signature=adhoc" in details or not re.search(
            r"^Authority=Apple (Distribution|Development): .+", details, re.MULTILINE):
        raise ValueError(f"Expected an Apple Distribution/Development signature: {path}")
    if distribution and not re.search(r"^Authority=Apple Distribution: .+", details, re.MULTILINE):
        raise ValueError(f"Expected an Apple Distribution signature for App Store upload: {path}")
    if f"TeamIdentifier={team}" not in details.splitlines():
        raise ValueError(f"Unexpected signing team: {path}")
    if timestamp and not re.search(r"^Timestamp=.+", details, re.MULTILINE):
        raise ValueError(f"Missing secure timestamp: {path}")


def xcframeworks(directory):
    expected = [directory / f"godot_firebase.ios.{target}.xcframework"
                for target in ("template_debug", "template_release")]
    for path in expected:
        if not path.is_dir():
            raise ValueError(f"Missing iOS XCFramework: {path}")
    return expected


def sign_directory(directory):
    identity, team, keychain = signing_identity()
    for path in xcframeworks(directory):
        # Sign inside-out after all layout, load-command and metadata changes.
        for bundle in [*framework_slices(path), path]:
            print(run("codesign", "--force", "--timestamp", "--sign", identity,
                      *(["--keychain", keychain] if keychain else []), bundle), file=sys.stderr, end="")
            verify_signature(bundle, team, timestamp=True)


def framework_slices(xcframework):
    with (xcframework / "Info.plist").open("rb") as source:
        metadata = plistlib.load(source)
    libraries = metadata.get("AvailableLibraries", [])
    frameworks = []
    variants = []
    for library in libraries:
        identifier = library.get("LibraryIdentifier", "")
        name = library.get("LibraryPath", "")
        if (not identifier or Path(identifier).name != identifier or identifier in {".", ".."}
                or not name.endswith(".framework") or Path(name).name != name):
            raise ValueError(f"Rebuild {xcframework}: expected framework slices, not bare dylibs")
        framework = xcframework / identifier / name
        if not framework.is_dir() or library.get("SupportedPlatform") != "ios":
            raise ValueError(f"Missing iOS framework slice: {framework}")
        frameworks.append(framework)
        variants.append(library.get("SupportedPlatformVariant", "device"))
    if sorted(variants) != ["device", "simulator"]:
        raise ValueError(f"Rebuild {xcframework}: expected one device and one simulator framework")
    return frameworks


def extract_archive(archive_path, destination):
    """Preserve executable modes; refuse paths/links outside the flat iOS layout."""
    with zipfile.ZipFile(archive_path) as archive:
        seen = set()
        for entry in archive.infolist():
            relative = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if (relative.is_absolute() or ".." in relative.parts or "\\" in entry.filename
                    or not relative.parts or relative.as_posix().casefold() in seen or stat.S_ISLNK(mode)):
                raise ValueError(f"Unsafe archive entry: {entry.filename}")
            # APFS is case-insensitive: Info.plist and info.plist would overwrite each other.
            seen.add(relative.as_posix().casefold())
            target = destination.joinpath(*relative.parts)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o755 if mode & 0o111 else 0o644)


def verify_package(path, team):
    with tempfile.TemporaryDirectory(prefix="ios-verify-") as temporary:
        root = Path(temporary)
        extract_archive(path, root)
        for framework in xcframeworks(root / "addons/firebase/bin/ios"):
            verify_xcframework(framework, team)


def verify_xcframework(path, team):
    verify_signature(path, team, timestamp=True)
    for slice_path in framework_slices(path):
        verify_signature(slice_path, team, timestamp=True)


def verify_ipa(path, team, distribution=False):
    with tempfile.TemporaryDirectory(prefix="ios-verify-") as temporary:
        root = Path(temporary)
        extract_archive(path, root)
        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected exactly one application in IPA/Payload")
        app = apps[0]
        frameworks = sorted(app.rglob("*.framework"))
        if not any("godot_firebase" in framework.name for framework in frameworks):
            raise ValueError("IPA contains no embedded Godot Firebase framework")
        # Check every embedded framework explicitly; --deep also covers nested
        # code such as extensions and dylibs. The expected team is the game's.
        for framework in frameworks:
            verify_signature(framework, team, distribution=distribution)
        verify_signature(app, team, deep=True, distribution=distribution)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check-identity", help="Check runner certificate/private-key availability")
    sign = commands.add_parser("sign-directory", help="Sign the final staged bin/ios directory")
    sign.add_argument("path", type=Path)
    for command in ("verify-package", "verify-xcframework", "verify-ipa"):
        verify = commands.add_parser(command)
        verify.add_argument("path", type=Path)
        verify.add_argument("--team-id", required=True, help="SDK team for ZIP; game team for IPA")
        if command == "verify-ipa":
            verify.add_argument("--distribution", action="store_true",
                                help="Require Apple Distribution on the app and all embedded frameworks before upload")
    args = parser.parse_args()
    try:
        if args.command == "check-identity":
            signing_identity()
        elif args.command == "sign-directory":
            sign_directory(args.path)
        elif args.command == "verify-package":
            verify_package(args.path, team_id(args.team_id))
        elif args.command == "verify-xcframework":
            verify_xcframework(args.path, team_id(args.team_id))
        else:
            verify_ipa(args.path, team_id(args.team_id), distribution=args.distribution)
    except (OSError, ValueError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        print(f"iOS signing failed: {error}", file=sys.stderr)
        return 1
    print(f"iOS signing: {args.command} passed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
