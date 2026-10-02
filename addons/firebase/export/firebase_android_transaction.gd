@tool
extends RefCounted
## Text-file updates for one game export. All writes are staged before originals
## move; commit failures restore them. This is not a power-loss atomic journal.


static func apply(changes: Dictionary) -> Dictionary:
	var staged := _stage(changes)
	return staged if staged.error != OK else _commit(staged.entries)


static func _stage(changes: Dictionary) -> Dictionary:
	var entries: Array[Dictionary] = []
	var paths := {}
	# Validate every target before creating any temporary file.
	for supplied_path in changes:
		if not supplied_path is String or not supplied_path.is_absolute_path():
			return _failure("Firebase export transaction requires absolute file paths.")
		if changes[supplied_path] != null and not changes[supplied_path] is String:
			return _failure("Firebase export transaction requires text or null for %s." % supplied_path)
		var path := ProjectSettings.globalize_path(supplied_path).simplify_path()
		if paths.has(path):
			return _failure("Firebase export transaction contains the same target twice: %s." % path)
		paths[path] = true
		if DirAccess.dir_exists_absolute(path):
			return _failure("Firebase export target is a directory, not a file: %s." % path)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			return _failure("Firebase export cannot replace a symbolic link: %s." % path)
		entries.append({"path": path, "contents": changes[supplied_path], "staged": "", "backup": "",
			"existed": FileAccess.file_exists(path), "backed_up": false, "installed": false})
	for entry in entries:
		if entry.contents == null:
			continue
		var error := DirAccess.make_dir_recursive_absolute(String(entry.path).get_base_dir())
		if error != OK:
			return _stage_failure(entries, "Cannot create export directory for %s (error %d)." % [entry.path, error])
		entry.staged = _temporary_path(entry.path, "staged")
		var file := FileAccess.open(entry.staged, FileAccess.WRITE)
		if file == null:
			return _stage_failure(entries, "Cannot stage Firebase export file %s (error %d)." % [entry.path, FileAccess.get_open_error()])
		file.store_string(entry.contents)
		file.flush()
		error = file.get_error()
		file.close()
		if error != OK:
			return _stage_failure(entries, "Cannot finish staging Firebase export file %s (error %d)." % [entry.path, error])
	return {"error": OK, "entries": entries}


static func _commit(entries: Array) -> Dictionary:
	for entry in entries:
		if entry.existed:
			entry.backup = _temporary_path(entry.path, "backup")
			var error := DirAccess.rename_absolute(entry.path, entry.backup)
			if error != OK:
				return _commit_failure(entries, "Cannot preserve Firebase export file %s (error %d)." % [entry.path, error])
			entry.backed_up = true
		elif FileAccess.file_exists(entry.path) or DirAccess.dir_exists_absolute(entry.path):
			return _commit_failure(entries, "Firebase export target appeared during preparation: %s." % entry.path)
		if not String(entry.staged).is_empty():
			var error := DirAccess.rename_absolute(entry.staged, entry.path)
			if error != OK:
				return _commit_failure(entries, "Cannot install Firebase export file %s (error %d)." % [entry.path, error])
			entry.installed = true
	var failures := PackedStringArray()
	for entry in entries:
		if entry.backed_up and DirAccess.remove_absolute(entry.backup) != OK:
			failures.append(entry.backup)
	if not failures.is_empty():
		return _failure("Firebase export files were updated, but these backup files could not be removed: %s." % ", ".join(failures))
	return {"error": OK}


static func _commit_failure(entries: Array, message: String) -> Dictionary:
	var failures := PackedStringArray()
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		if entry.installed and DirAccess.remove_absolute(entry.path) != OK:
			failures.append("cannot remove new file %s" % entry.path)
			# Never overwrite an unexpected file or discard its original backup.
			continue
		if entry.backed_up and DirAccess.rename_absolute(entry.backup, entry.path) != OK:
			failures.append("restore %s from preserved backup %s" % [entry.path, entry.backup])
	failures.append_array(_remove_staged(entries))
	if not failures.is_empty():
		message += " Recovery required: " + "; ".join(failures)
	return _failure(message)


static func _stage_failure(entries: Array, message: String) -> Dictionary:
	var failures := _remove_staged(entries)
	if not failures.is_empty():
		message += " Remove leftover temporary files: " + "; ".join(failures)
	return _failure(message)


static func _remove_staged(entries: Array) -> PackedStringArray:
	var failures := PackedStringArray()
	for entry in entries:
		if not String(entry.staged).is_empty() and FileAccess.file_exists(entry.staged):
			if DirAccess.remove_absolute(entry.staged) != OK:
				failures.append(entry.staged)
	return failures


static func _temporary_path(target: String, kind: String) -> String:
	var parent := target.get_base_dir()
	while true:
		var path := parent.path_join(".godot-firebase-%s-%d-%d.tmp" % [kind, Time.get_ticks_usec(), randi()])
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
			return path
	return ""


static func _failure(message: String) -> Dictionary:
	return {"error": ERR_CANT_CREATE, "message": message}
