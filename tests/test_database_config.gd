extends FirebaseTest

const SETTING := "firebase/database/persistence_enabled"

func _run() -> void:
	var had_setting := ProjectSettings.has_setting(SETTING)
	var old_value: Variant = ProjectSettings.get_setting(SETTING)
	if had_setting:
		ProjectSettings.clear(SETTING)
	var firebase: Node = FirebaseNode.new()
	var backend: Object = firebase._create_backend("database", false)
	check(backend != null and not backend.persistence_enabled, "missing persistence setting defaults false")
	ProjectSettings.set_setting(SETTING, true)
	backend = firebase._create_backend("database", false)
	check(backend != null and backend.persistence_enabled, "persistence setting reaches backend initialization")
	ProjectSettings.set_setting(SETTING, "true")
	backend = firebase._create_backend("database", false)
	check(backend == null, "invalid persistence setting makes Database unavailable")
	check(firebase._create_backend("functions", false) != null, "invalid Database setting does not affect Functions")
	ProjectSettings.clear(SETTING)
	if had_setting:
		ProjectSettings.set_setting(SETTING, old_value)
	firebase.free()
