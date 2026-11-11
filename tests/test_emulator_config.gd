extends FirebaseTest
## firebase/<module>/emulator_host reaches backend initialization, an invalid value
## makes that module unavailable and release exports ignore the setting.

const HOSTS := {"auth": "10.0.2.2:9099", "firestore": "127.0.0.1:8080", "storage": "localhost:9199", "database": "192.168.0.5:9000", "functions": "[::1]:5001"}
const INVALID: Array = ["http://10.0.2.2:9099", "10.0.2.2", ":9099", "10.0.2.2:", "10.0.2.2:0", "10.0.2.2:65536", "10.0.2.2:+80", "10.0.2.2:080", "10.0.2.2:123456", "10.0.2.2:80a", 9099]


func _run() -> void:
	for value in INVALID:
		check(not FirebaseNode._is_valid_emulator_host(value), "%s is not a valid emulator host" % str(value))
	var firebase: Node = FirebaseNode.new()
	check(not firebase._release, "test run is a debug build")
	for module in FirebaseNode.EMULATOR_MODULES:
		var setting := "firebase/%s/emulator_host" % module
		check(not ProjectSettings.has_setting(setting), "%s is unset in the test project" % setting)
		check(_emulator(firebase, module) == "", "%s emulator is off by default" % module)
		ProjectSettings.set_setting(setting, HOSTS[module])
		check(_emulator(firebase, module) == HOSTS[module], "%s reaches backend initialization" % setting)
		firebase._release = true
		check(_emulator(firebase, module) == "", "release export ignores %s" % setting)
		ProjectSettings.set_setting(setting, "http://10.0.2.2:9099")
		check(_emulator(firebase, module) == "", "release export ignores an invalid %s" % setting)
		firebase._release = false
		check(_emulator(firebase, module) == null, "invalid %s makes %s unavailable" % [setting, module])
		ProjectSettings.clear(setting)

	# Feature overrides give Android its own host, as in project.godot.
	ProjectSettings.set_setting("firebase/auth/emulator_host", "127.0.0.1:9099")
	ProjectSettings.set_setting("firebase/auth/emulator_host.debug", "10.0.2.2:9099")
	check(_emulator(firebase, "auth") == "10.0.2.2:9099", "feature override of emulator_host applies")
	ProjectSettings.clear("firebase/auth/emulator_host.debug")
	ProjectSettings.clear("firebase/auth/emulator_host")

	ProjectSettings.set_setting("firebase/database/persistence_enabled", true)
	ProjectSettings.set_setting("firebase/database/emulator_host", HOSTS.database)
	var database: Object = firebase._create_backend("database", false)
	check(database.persistence_enabled and database.emulator_host == HOSTS.database, "database gets persistence and emulator in order")
	ProjectSettings.clear("firebase/database/persistence_enabled")
	ProjectSettings.clear("firebase/database/emulator_host")
	firebase.free()


## The emulator host the module's backend was initialized with; null without a backend.
func _emulator(firebase: Node, module: String) -> Variant:
	var backend: Object = firebase._create_backend(module, false)
	return null if backend == null else backend.emulator_host
