#!/usr/bin/env python
# Builds the Godot Firebase GDExtension with the selected modules.
#
#   scons platform=macos target=template_debug modules=auth,firestore
#   scons platform=ios arch=arm64 ios_simulator=no target=template_release modules=auth
#
# Dependencies come from tools/bootstrap.sh; tools/build.sh runs every variant.

import glob
import os
import subprocess

FIREBASE_CPP = "third_party/firebase_cpp_sdk"
FIREBASE_IOS = "third_party/Firebase"

# Firebase C++ libraries and Firebase iOS SDK folders (from Firebase.zip) per module.
CORE = {"cpp": ["firebase_app"], "ios_frameworks": ["FirebaseCore", "FirebaseCoreInternal", "FirebaseInstallations", "GoogleUtilities", "FBLPromises", "nanopb"]}
MODULES = {
    "auth": {"cpp": ["firebase_auth"], "ios_folder": "FirebaseAuth", "system_frameworks": ["AuthenticationServices", "GameKit", "SafariServices"]},
    "firestore": {"cpp": ["firebase_firestore"], "ios_folder": "FirebaseFirestore", "system_frameworks": []},
}

ARGUMENTS.setdefault("api_version", "4.7")
ARGUMENTS.setdefault("ios_min_version", "15.0")
env = SConscript("third_party/godot-cpp/SConstruct")

options = Variables([], ARGUMENTS)
options.Add("modules", "Comma-separated modules: " + ",".join(MODULES), ",".join(MODULES))
options.Update(env)
Help(options.GenerateHelpText(env))

modules = [name.strip() for name in env["modules"].split(",") if name.strip()]
unknown = [name for name in modules if name not in MODULES]
if unknown or not modules:
    Exit("modules must be a non-empty subset of %s, got %s" % (",".join(MODULES), env["modules"]))

platform = env["platform"]
if platform not in ("ios", "macos"):
    Exit("platform=%s is not supported yet (ios, macos)" % platform)

env.Append(CPPPATH=["src", FIREBASE_CPP + "/include"])
env.Append(CPPDEFINES=["GODOT_FIREBASE_" + name.upper() for name in modules])

sources = ["src/register_types.cpp"] + Glob("src/core/*.cpp")
for name in modules:
    sources += Glob("src/%s/*.cpp" % name)
if "auth" in modules:
    sources += ["src/auth/platform/platform_credentials_ios.mm" if platform == "ios" else "src/auth/platform/platform_credentials_stub.cpp"]

cpp_libraries = [lib for name in modules for lib in MODULES[name]["cpp"]] + CORE["cpp"]


def xcrun(*args):
    return subprocess.check_output(["xcrun"] + list(args), text=True).strip()


def first_existing(patterns, what):
    for pattern in patterns:
        matches = sorted(glob.glob(pattern))
        if matches:
            return matches[0]
    Exit("%s not found; run tools/bootstrap.sh (looked for %s)" % (what, ", ".join(patterns)))


def link_static_framework(xcframework, slice_name):
    name = os.path.basename(xcframework)[: -len(".xcframework")]
    framework_dir = os.path.join(xcframework, slice_name)
    if not os.path.isdir(os.path.join(framework_dir, name + ".framework")):
        Exit("%s has no %s slice" % (xcframework, slice_name))
    env.Append(LINKFLAGS=["-F", framework_dir, "-framework", name])


if platform == "macos":
    # Firebase desktop libraries are a beta for development builds (editor, tests).
    lib_dir = first_existing([FIREBASE_CPP + "/libs/darwin/universal", FIREBASE_CPP + "/libs/darwin/*"], "Firebase C++ desktop libraries")
    env.Append(LIBPATH=[lib_dir], LIBS=cpp_libraries)
    for framework in ["CoreFoundation", "Foundation", "GSS", "Kerberos", "Security", "SystemConfiguration"]:
        env.Append(LINKFLAGS=["-framework", framework])
    env.Append(LIBS=["pthread"])
else:
    simulator = env["ios_simulator"]
    slice_name = "ios-arm64_x86_64-simulator" if simulator else "ios-arm64"
    sdk = "iphonesimulator" if simulator else "iphoneos"
    for lib in cpp_libraries:
        # The C++ SDK ships firebase_app as firebase.xcframework.
        framework = "firebase" if lib == "firebase_app" else lib
        link_static_framework(first_existing([FIREBASE_CPP + "/xcframeworks/%s.xcframework" % framework], framework + ".xcframework"), slice_name)
    linked = set()
    folders = [(FIREBASE_IOS + "/FirebaseAnalytics", CORE["ios_frameworks"])] + [(FIREBASE_IOS + "/" + MODULES[name]["ios_folder"], None) for name in modules]
    for folder, only in folders:
        for xcframework in sorted(glob.glob(folder + "/*.xcframework")):
            name = os.path.basename(xcframework)[: -len(".xcframework")]
            if name in linked or (only is not None and name not in only):
                continue
            linked.add(name)
            link_static_framework(xcframework, slice_name)
    system_frameworks = ["Foundation", "UIKit", "Security", "SystemConfiguration", "CoreTelephony"]
    system_frameworks += [framework for name in modules for framework in MODULES[name]["system_frameworks"]]
    for framework in system_frameworks:
        env.Append(LINKFLAGS=["-framework", framework])
    # Firebase static frameworks contain Swift and Objective-C categories.
    toolchain = os.path.dirname(os.path.dirname(xcrun("--sdk", sdk, "--find", "swiftc")))
    env.Append(LINKFLAGS=[
        "-ObjC",
        "-L" + os.path.join(toolchain, "lib", "swift", sdk),
        "-L" + os.path.join(xcrun("--sdk", sdk, "--show-sdk-path"), "usr", "lib", "swift"),
        "-Wl,-rpath,/usr/lib/swift",
    ])
    env.Append(LIBS=["c++", "z", "sqlite3"])

suffix = ".%s.%s%s" % (platform, env["target"], ".simulator" if platform == "ios" and env["ios_simulator"] else "")
library = env.SharedLibrary("build/%s/libgodot_firebase%s%s" % (platform, suffix, env["SHLIBSUFFIX"]), source=sources)
Default(library)
