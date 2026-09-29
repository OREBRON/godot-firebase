# TODO

Handover state (2026-09-29). Read `AGENTS.md` first; it holds the code rules and the module contract.

## Current state

- Modules: core (app), `auth`, `firestore`, `storage`, `database` (Realtime Database), `functions`.
- GDScript APIs and mocks exist for all five modules; `tools/run_tests.sh` passes (7 tests).
- Native C++ exists for all five modules. Since 2026-09-29 it compiles and links locally for iOS device and simulator (`tools/build.sh --modules auth,firestore,storage,database,functions`, Xcode 27, NOUNDEFS). It has **not run on a device** yet, and CI has not reached the build step.
- Target platforms are iOS and Android only. The macOS library is an editor stub without Firebase (`GODOT_FIREBASE_EDITOR_STUB`); the editor and tests use the mocks.
- Target engine is Godot 4.7.2. godot-cpp has no 4.7 tag, so `master` is pinned in `tools/versions.env` and built with `api_version=4.7`.

## 1. Get CI to a green build (blocker)

- [ ] **Runner.** Still open; needs someone with access to the runner machine (repo-level `gh api .../actions/runners` lists none, org level needs admin). The workflow now fails early below `MIN_FREE_GB` free disk and cleans archives, build products and partial extractions after every run. CI run 36479560583 failed after 11 minutes with "The self-hosted runner lost communication with the server". Its runner is `CYC-MacBook-Pro`, label `[self-hosted, macOS, ARM64]`, shared with the moonlight-bakery TestFlight builds. The first run 36478910217 had filled its disk while extracting the full Firebase C++ SDK.
  - Check that the runner is online.
  - Check its free disk space.
  - Remove leftovers under `_work/godot-firebase/godot-firebase-third-party`. The partial extraction is redone automatically, but the old zip may still be there.
- [x] **Extraction.** Verified end to end on 2026-09-29 (third_party: 416 MB C++ SDK, 1.1 GB Firebase, 37 MB godot-cpp). `tools/bootstrap.sh` extracts only:
  - iOS `device-arm64` and `simulator-arm64` libraries, plus Android `arm64-v8a` libraries, for all six C++ libraries;
  - `include/`;
  - the Android gradle and `.pro` helpers;
  - the Firebase.zip folders `FirebaseAnalytics`, `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`, `FirebaseDatabase`, `FirebaseFunctions`.
- [x] **Assumptions in `SConstruct`.** Verified by a local build, except the last one, which needs a device:
  - Firebase.zip slice names `ios-arm64` and `ios-arm64_x86_64-simulator`.
  - The core framework list from the `FirebaseAnalytics` folder.
  - The Swift runtime link flags (FirebaseAuth and Firestore contain Swift).
  - `-ObjC` and the system frameworks list.
  - A shared library as the iOS target (see section 3).
- [x] **Resource bundles.** SConstruct writes `build/ios/resource_bundles.txt` from the frameworks it links; `tools/build.sh` copies that list (16 bundles for all modules).
- [x] **Packaging.** `tools/package.sh` treats every folder with `firebase_<name>.gd` as a module.
- [x] **CI variants.** Default `auth`, `auth,firestore` and all five modules; `workflow_dispatch` input `variants` overrides them.

## 2. Native modules for storage, database, functions

Follow the existing pattern: one class per module, `FirebaseXNative : FirebaseModuleNative`. Method names and signals must match the mocks exactly (`addons/godot_firebase/<module>/firebase_<module>_mock.gd`). Register each class in `src/register_types.cpp` and each module in `SConstruct` `MODULES`.

Done on 2026-09-29; compiled and linked, not yet run on a device.

- [x] **`src/core/variant_convert.{h,cpp}`:** `godot::Variant` ↔ `firebase::Variant`, shared by `database` and `functions`.
  - Types: null, bool, int, float, String and StringName, Array and packed arrays, Dictionary with String keys.
  - Unsupported types return a reason and never abort.
- [x] **`storage`** (`firebase::storage::Storage::GetInstance`):
  - `upload_bytes(path, data, content_type)` returns metadata. `PutBytes` needs its buffer alive until the future completes; hold it in a `shared_ptr` captured by the completion.
  - `download_bytes(path, max_size)`: `GetBytes` into a `shared_ptr` buffer, then trim it to `*result`.
  - `get_download_url`, `get_metadata`, `delete_file`.
  - Metadata: `{path, name, size, content_type, updated}`, where `updated` is milliseconds and the `const char*` fields may be null.
  - Error codes used by the mock: 2 = object not found, 10 = download size exceeded. Checked against `firebase/storage/common.h`.
- [x] **`database`** (`firebase::database::Database::GetInstance`):
  - `get_value` returns `{key, exists, value}`. Also `set_value`, `update_children` (keys may be child paths), `remove_value`.
  - `push_value`: `PushChild()` then `SetValue`; the result is the new key.
  - `listen_value` / `remove_listener`: one `ValueListener` subclass per listener, stored with its `DatabaseReference`. It emits `value_changed(listener_id, ok, snapshot, code, message)` through `FirebaseModuleNative::emit_deferred_to`, reached from the nested class `FirebaseDatabaseNative::Listener`.
  - `FirebaseDatabase.SERVER_TIMESTAMP` is `{".sv": "timestamp"}`, the wire format, so it passes through conversion unchanged.
  - Validate paths natively too: no `. # $ [ ]`.
- [x] **`functions`** (`firebase::functions::Functions::GetInstance(app, region)`):
  - The region comes from project setting `firebase/functions/region` (default `us-central1`), read through `ProjectSettings`.
  - `call_function(name, data)`: `GetHttpsCallable(name).Call(variant)`, returns `result.data()`.
  - The name cannot be `call` because it clashes with `Object.call`.

## 3. Device verification (Moonlight Bakery pilot)

- [ ] Download `GoogleService-Info.plist` for bundle id `com.orebron.moonlightbakery` and put it at `res://` root.
- [ ] Set the entitlements in the export preset (see README): Sign in with Apple and Game Center.
- [ ] Check that Godot 4.7.2 iOS export embeds the dynamic xcframework from the `.gdextension` file.
- [ ] Check that `add_apple_embedded_platform_bundle_file` copies the `*.bundle` resources and the plist into the app.
- [ ] Run on iPhone:
  - anonymous sign-in, then `link_with_apple`, `link_with_game_center`, `delete_account`;
  - Firestore write, read, query and listener;
  - Storage upload and download, a Database listener, one callable function.
- [ ] Measure the IPA size per variant; the moonlight repo tracks app size in `docs/app-size.md`.
- [ ] Wire the placeholder Apple and Google buttons in moonlight `scripts/home_settings.gd` `_sign_in_buttons()`. Google sign-in is not implemented yet: it needs the GoogleSignIn SDK and `GoogleAuthProvider::GetCredential(id_token, nullptr)`.

## 4. Android

- [ ] `FirebaseAppNative::initialize()` on Android needs `App::Create(jni_env, activity)`. Get the activity from a small Godot Android plugin v2 in Kotlin, or through JNI from `org.godotengine.godot.Godot`.
- [ ] Gradle: `firebase_cpp_sdk/Android/firebase_dependencies.gradle` plus the `.pro` ProGuard files. Turn `google-services.json` into resources with `generate_xml_from_google_services_json.py`.
- [ ] Build `arm64-v8a` only; the moonlight Play build exports only that ABI.
- [ ] Platform sign-in: Play Games via `PlayGamesAuthProvider`, which needs a server auth code. `src/auth/platform/` currently has only the iOS implementation.

## 5. Docs

- [x] README: five modules, editor stub, storage, database and functions usage, verified build state.
- [x] AGENTS.md: module contract for five modules and the full registration list.
