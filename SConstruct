#!/usr/bin/env python
# Builds the Godot Firebase GDExtension with the selected modules.
#
#   scons platform=ios arch=arm64 ios_simulator=no target=template_release modules=auth
#   scons platform=android arch=arm64 target=template_release modules=auth
#
# Dependencies come from tools/bootstrap.sh; tools/build.sh runs every variant.
# tools/build_desktop_stub.py builds the desktop editor stubs (no SDK/bindings).

import glob
import os
import re
import subprocess

FIREBASE_CPP = "third_party/firebase_cpp_sdk"
FIREBASE_IOS = "third_party/Firebase"

# Firebase C++ libraries and Firebase iOS SDK folders (from Firebase.zip) per module.
CORE = {"cpp": ["firebase_app"], "ios_frameworks": ["FirebaseCore", "FirebaseCoreInternal", "FirebaseInstallations", "GoogleUtilities", "FBLPromises", "nanopb"]}
MODULES = {
    "auth": {"cpp": ["firebase_auth"], "ios_folder": "FirebaseAuth", "system_frameworks": ["AuthenticationServices", "GameKit", "SafariServices", "LocalAuthentication", "CoreGraphics", "CoreText"]},
    "firestore": {"cpp": ["firebase_firestore"], "ios_folder": "FirebaseFirestore", "system_frameworks": ["Network"]},
    "storage": {"cpp": ["firebase_storage"], "ios_folder": "FirebaseStorage", "system_frameworks": []},
    "database": {"cpp": ["firebase_database"], "ios_folder": "FirebaseDatabase", "system_frameworks": []},
    "functions": {"cpp": ["firebase_functions"], "ios_folder": "FirebaseFunctions", "system_frameworks": []},
    "analytics": {"cpp": ["firebase_analytics"], "ios_folder": "FirebaseAnalytics", "system_frameworks": ["StoreKit", "AdSupport"]},
    "remote_config": {"cpp": ["firebase_remote_config"], "ios_folder": "FirebaseRemoteConfig", "system_frameworks": []},
    "crashlytics": {"cpp": [], "ios_folder": "FirebaseCrashlytics", "system_frameworks": []},
}
# tools/build.sh copies the resource bundles listed here into the addon.
RESOURCE_BUNDLES_LIST = "build/ios/resource_bundles.txt"
ios_framework_dirs = []

with open("tools/versions.env") as versions:
    ARGUMENTS.setdefault("api_version", re.search(r"^GODOT_API_VERSION=(.*)$", versions.read(), re.M).group(1))
ARGUMENTS.setdefault("ios_min_version", "15.0")
# Keep product flags out of godot-cpp's build environment, so changing module
# selections does not recompile the entire engine binding library.
env = SConscript("third_party/godot-cpp/SConstruct").Clone()

options = Variables([], ARGUMENTS)
options.Add("modules", "Comma-separated modules: " + ",".join(MODULES), ",".join(MODULES))
options.Update(env)
Help(options.GenerateHelpText(env))

modules = [name.strip() for name in env["modules"].split(",") if name.strip()]
unknown = [name for name in modules if name not in MODULES]
if unknown or not modules or len(set(modules)) != len(modules):
    Exit("modules must be a non-empty subset of %s, got %s" % (",".join(MODULES), env["modules"]))

platform = env["platform"]
if platform not in ("ios", "android"):
    Exit("platform=%s is not supported (ios, android); desktop stubs come from tools/build_desktop_stub.py" % platform)

env.Append(CPPPATH=["src", FIREBASE_CPP + "/include"])
env.Append(CPPDEFINES=["GODOT_FIREBASE_" + name.upper() for name in modules])
sources = ["src/register_types.cpp"]
sources += Glob("src/core/*.cpp")
if platform == "ios":
    sources += Glob("src/core/*.mm")
for name in modules:
    sources += Glob("src/%s/*.cpp" % name)
if "auth" in modules:
    sources += ["src/auth/platform/platform_credentials_ios.mm" if platform == "ios" else "src/auth/platform/platform_credentials_android.cpp"]

if "crashlytics" in modules:
    sources += ["src/crashlytics/platform/crashlytics_ios.mm" if platform == "ios" else "src/crashlytics/platform/crashlytics_android.cpp"]

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
    ios_framework_dirs.append(framework_dir)


def resource_bundles(xcframework):
    """*.bundle directories (certificates, privacy manifests) of the device slice."""
    bundles = []
    for root, dirs, _ in os.walk(os.path.join(xcframework, "ios-arm64")):
        for name in sorted(dirs):
            if name.endswith(".bundle"):
                bundles.append(os.path.join(root, name))
                dirs.remove(name)
    return bundles


if platform == "android":
    lib_dir = FIREBASE_CPP + "/libs/android/arm64-v8a"
    for lib in cpp_libraries:
        first_existing([lib_dir + "/lib%s.a" % lib], "lib%s.a" % lib)
    env.Append(LIBPATH=[lib_dir], LIBS=cpp_libraries + ["log"])
    env.Append(LINKFLAGS=["-Wl,--no-undefined", "-Wl,--build-id=sha1"])

if platform == "ios":
    simulator = env["ios_simulator"]
    slice_name = "ios-arm64_x86_64-simulator" if simulator else "ios-arm64"
    sdk = "iphonesimulator" if simulator else "iphoneos"
    lib_dir = FIREBASE_CPP + "/libs/ios/" + ("simulator-arm64" if simulator else "device-arm64")
    for lib in cpp_libraries:
        first_existing([lib_dir + "/lib%s.a" % lib], "lib%s.a" % lib)
    env.Append(LIBPATH=[lib_dir], LIBS=cpp_libraries)
    linked = set()
    bundles = []
    folders = [(FIREBASE_IOS + "/FirebaseAnalytics", CORE["ios_frameworks"])] + [(FIREBASE_IOS + "/" + MODULES[name]["ios_folder"], None) for name in modules]
    if "auth" in modules:
        first_existing(["third_party/GoogleSignIn/GoogleSignIn.xcframework"], "Google Sign-In (run tools/build_google_signin_ios.sh)")
        folders += [("third_party/GoogleSignIn", None)]
        bundles += sorted(glob.glob("third_party/GoogleSignIn/resources/*.bundle"))
    for folder, only in folders:
        for xcframework in sorted(glob.glob(folder + "/*.xcframework")):
            name = os.path.basename(xcframework)[: -len(".xcframework")]
            if name in linked or (only is not None and name not in only):
                continue
            linked.add(name)
            link_static_framework(xcframework, slice_name)
            bundles += resource_bundles(xcframework)
    os.makedirs(os.path.dirname(RESOURCE_BUNDLES_LIST), exist_ok=True)
    with open(RESOURCE_BUNDLES_LIST, "w") as bundle_list:
        bundle_list.writelines(bundle + "\n" for bundle in bundles)
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
library_name = "libgodot_firebase%s%s" % (suffix, env["SHLIBSUFFIX"])
# The framework wrapper sets the final @rpath before SDK signing. Reserve room
# for its longer install name; the intermediate dylib still has a usable ID.
if platform == "ios":
    env.Append(LINKFLAGS=["-Wl,-install_name,@rpath/" + library_name, "-Wl,-headerpad_max_install_names"])
# godot-cpp compiles .mm through CXXCOM; framework/ARC flags must be on these
# Objective-C++ objects, rather than OBJCXXFLAGS which that command omits.
if platform == "ios":
    objc_flags = list(env["CXXFLAGS"]) + ["-fobjc-arc"]
    for framework_dir in ios_framework_dirs:
        objc_flags += ["-F", framework_dir]
    sources = [env.SharedObject(source, CXXFLAGS=objc_flags) if str(source).endswith(".mm") else source for source in sources]
library = env.SharedLibrary("build/%s/%s" % (platform, library_name), source=sources)
Default(library)
