extends FirebaseTest
## Desktop installs must load the stub and start the real API layer with mocks.

const DESCRIPTOR := "res://addons/firebase/godot_firebase.gdextension"
const DESKTOP_FEATURES := ["windows.x86_64", "linux.x86_64", "macos.arm64", "macos.x86_64"]


func _run() -> void:
	if OS.has_feature("mobile"):
		print("test_desktop_extension.gd: skipped (desktop only)")
		return
	var config := ConfigFile.new()
	check(config.load(DESCRIPTOR) == OK, "desktop descriptor is readable")
	for features in DESKTOP_FEATURES:
		check(config.has_section_key("libraries", features), "%s has an explicit library mapping" % features)
		if config.has_section_key("libraries", features):
			check(FileAccess.file_exists(config.get_value("libraries", features)), "%s library is installed (git lfs pull)" % features)
	check(not config.has_section_key("libraries", "macos.debug"), "generic macOS debug mapping cannot select the wrong architecture")
	check(not config.has_section_key("libraries", "macos.release"), "generic macOS release mapping cannot select the wrong architecture")
	check(GDExtensionManager.is_extension_loaded(DESCRIPTOR), "desktop GDExtension loaded successfully")
	check(not ClassDB.class_exists(&"FirebaseAppNative"), "desktop stub does not register mobile Firebase classes")
	var firebase: Node = FirebaseNode.new()
	root.add_child(firebase)
	for module in FirebaseNode.MODULES:
		if ResourceLoader.exists("res://addons/firebase/%s/firebase_%s.gd" % [module, module]):
			check(firebase.get(module) != null and firebase.is_available(module) and firebase.is_mock(module), "%s API starts with its mock backend" % module)
	var result: FirebaseResult = await firebase.auth.sign_in_anonymously().wait()
	check(result.ok, "loaded desktop stub allows API requests through the mock backend")
