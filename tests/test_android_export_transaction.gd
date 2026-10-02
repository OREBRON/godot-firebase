extends FirebaseTest

const HELPER := "res://addons/firebase/export/firebase_android_transaction.gd"
var _helper: GDScript
var _directory := ""


func _run() -> void:
	check(FileAccess.file_exists(HELPER), "Android export file updates use rollback on failure")
	if not FileAccess.file_exists(HELPER):
		return
	_helper = load(HELPER)
	_directory = "user://android-transaction-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_directory)
	var existing := _directory.path_join("existing.txt")
	var added := _directory.path_join("generated.txt")
	var removed := _directory.path_join("removed.txt")
	_write(existing, "game original")
	_write(removed, "old generated file")
	var result: Dictionary = _helper.apply({existing: "updated", added: "new", removed: null})
	check(result.error == OK, "file transaction commits writes and removal")
	check(_read(existing) == "updated" and _read(added) == "new", "committed contents match desired files")
	check(not FileAccess.file_exists(removed), "committed removal deletes only its target")
	check(DirAccess.get_files_at(_directory).size() == 2, "successful transaction removes temporary files and backups")
	result = _helper.apply({existing: "updated", added: "new", removed: null})
	check(result.error == OK, "repeating the same desired files is safe")

	var directory_conflict := _directory.path_join("google-services.json")
	DirAccess.make_dir_recursive_absolute(directory_conflict)
	result = _helper.apply({added: "must not change", directory_conflict: "configuration"})
	check(result.error != OK and _read(added) == "new", "directory conflict fails before changing an earlier target")
	check(DirAccess.get_files_at(_directory).size() == 2, "directory conflict leaves no orphan staging files")
	DirAccess.remove_absolute(directory_conflict)
	result = _helper.apply({added: "retry", directory_conflict: "configuration"})
	check(result.error == OK and _read(added) == "retry", "correcting conflict allows retry without manual generated-file cleanup")

	# A parent that is a file forces a real staging error after the first stage.
	result = _helper.apply({added: "must not change", existing.path_join("blocked.txt"): "blocked"})
	check(result.error != OK and _read(added) == "retry", "staging failure changes no existing files")
	check(DirAccess.get_files_at(_directory).size() == 3, "staging failure cleans earlier temporary files")

	_write(removed, "restore removed file")
	var brand_new := _directory.path_join("brand-new.txt")
	var staged: Dictionary = _helper._stage({existing: "uncommitted", removed: null, brand_new: "uncommitted", added: "uncommitted"})
	check(staged.error == OK, "rollback fixture stages real transaction files")
	if staged.error == OK:
		# Simulate a staged file disappearing before its rename. Earlier changes
		# have committed by then, so this exercises restoration, not just preflight.
		DirAccess.remove_absolute(staged.entries.back().staged)
		result = _helper._commit(staged.entries)
		check(result.error != OK, "missing staged file reports commit failure")
		check(_read(existing) == "updated" and _read(added) == "retry", "failed commit restores original overwritten files")
		check(_read(removed) == "restore removed file", "failed commit restores removed file")
		check(not FileAccess.file_exists(brand_new), "failed commit removes its newly created file")
		check(DirAccess.get_files_at(_directory).size() == 4, "rollback leaves no staging files or backups")
	result = _helper.apply({"relative.txt": "invalid"})
	check(result.error != OK, "relative paths are rejected before filesystem changes")
	result = _helper.apply({added: 42})
	check(result.error != OK and _read(added) == "retry", "non-text payload is rejected without truncating target")
	var absolute := ProjectSettings.globalize_path(added)
	result = _helper.apply({added: "first", absolute: "second"})
	check(result.error != OK and _read(added) == "retry", "two aliases for the same target are rejected")
	for name in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)
