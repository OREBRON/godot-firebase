# Crashlytics game integration smoke

This fixture is separate from the reusable SDK binary and production API. No upload or crash is triggered automatically. Copy it into a disposable game with the Firebase autoload and that game's JSON/plist. Configure the game's Crashlytics export setting before a fresh installation to test startup-disabled collection. Native SDK overrides persist across launches; a runtime disable call alone does not prove startup privacy.

Attach `nonfatal.gd` to a scene. Its result confirms a local call only. Restart the app and inspect the correct Firebase app in the console after ingestion. Android retains `GodotSmokeError` in the message under `GodotNonfatalError`; iOS uses the exception model name. The supplied GDScript stack is explicit; unrelated Godot errors are not automatically reported.

For a native-crash test, build the separate fixture from this directory with the repository's SCons/Python environment, `platform=android arch=arm64 target=template_debug` or `platform=ios arch=arm64 target=template_debug`. Then copy `crashlytics_smoke.gdextension.example` to `crashlytics_smoke.gdextension` in the disposable game. The fixture build and source reject release builds. The descriptor exposes only debug mobile entries; remove this directory from production games. iOS exporting this standalone dynamic fixture may require embedding/signing it in the Xcode game project. Connect a deliberate test button to `trigger_native_crash()`, run without an attached debugger, trigger once, then restart. Inspect `did_crash_previous_execution()` and the known `godot_firebase_crashlytics_smoke_fault` native frame after upload. This path still needs device/Xcode-export acceptance.

Keep the exact exported binary, matching unstripped ELF or dSYM, and the game's R8 mapping together per build/ABI. SDK symbols cover SDK frames; engine frames require matching Godot export-template symbols. For the fixture's dylib create its dSYM with `dsymutil` before stripping. Use the same process for the final iOS executable that contains statically linked SDK code.

Verification makes no network requests:

```sh
python3 tools/verify_crashlytics_symbols.py android --binary game/lib/arm64-v8a/libgodot_firebase.so --symbols symbols/arm64-v8a/libgodot_firebase.so --readelf /path/to/ndk/llvm-readelf --mapping game/build/outputs/mapping/release/mapping.txt --output symbols/android-identity.json
python3 tools/verify_crashlytics_symbols.py ios --binary Game.app/Game --symbols Game.app.dSYM --output symbols/ios-identity.json
```

The verifier rejects missing/mismatched IDs and Android symbol files without DWARF/full symbol tables. R8 mapping hashes record provenance; ELF IDs do not validate mapping-to-APK correspondence. Retain mapping from the same minified export.

Only after verification, explicitly upload to the game's Firebase app:

```sh
tools/upload_crashlytics_symbols.sh android --binary game/lib/arm64-v8a/libgodot_firebase.so --symbols symbols/arm64-v8a/libgodot_firebase.so --readelf /path/to/ndk/llvm-readelf --config game/google-services.json --gradle-project game --variant Release --upload-tool /path/to/game/gradlew --mapping game/build/outputs/mapping/release/mapping.txt
tools/upload_crashlytics_symbols.sh ios --binary Game.app/Game --symbols Game.app.dSYM --config game/GoogleService-Info.plist --upload-tool /path/to/FirebaseCrashlytics/upload-symbols
```

Android uses the game export's generated Gradle configuration, verifies identical game JSON, and enables explicit symbol upload through a project property. Optional mapping upload requires the supplied mapping to equal that variant's output. Run once per unstripped-library directory/ABI as appropriate. No credentials or game configuration belong in prebuilt SDK artifacts.

Acceptance still requires two independently configured games consuming the same SDK artifacts, a startup-disabled fresh install, crash/restart, R8-enabled Android export, signed iOS archive, matching IDs, and console symbolication of the known frame. A mock, compilation, or matching-ID check does not establish any of those runtime outcomes.
