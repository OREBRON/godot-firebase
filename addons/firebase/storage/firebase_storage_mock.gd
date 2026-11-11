class_name FirebaseStorageMock
extends FirebaseMockModule
## In-memory FirebaseStorageNative. Nothing is persisted. Uploads and downloads
## finish on the next idle frame; cancel_transfer() before that stops them.

## Storage error codes (firebase::storage::Error).
const UNKNOWN := 1
const OBJECT_NOT_FOUND := 2
const DOWNLOAD_SIZE_EXCEEDED := 10
const CANCELLED := 11
## Content type the SDKs upload when none is given.
const DEFAULT_CONTENT_TYPE := "application/octet-stream"

## Path -> {bytes, content_type, updated} with optional cache_control and custom_metadata.
var files: Dictionary[String, Dictionary] = {}
## Request id -> {bytes_transferred, total_bytes} of an unfinished upload or download.
var _transfers: Dictionary[int, Dictionary] = {}


func upload_bytes(path: String, data: PackedByteArray, content_type: String) -> int:
	var id := _take_id()
	if content_type.to_utf8_buffer().has(0):
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "content_type must not contain NUL")
	elif not _fail_if_requested(id):
		_upload(id, path, data.duplicate(), content_type)
	return id


func upload_file(path: String, local_path: String, content_type: String) -> int:
	var id := _take_id()
	if content_type.to_utf8_buffer().has(0):
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "content_type must not contain NUL")
	elif not _fail_if_requested(id):
		var data := FileAccess.get_file_as_bytes(local_path)
		if FileAccess.get_open_error() != OK:
			_finish_error(id, UNKNOWN, "cannot read %s" % local_path)
		else:
			_upload(id, path, data, content_type)
	return id


func download_bytes(path: String, max_size: int) -> int:
	var id := _take_id()
	if max_size <= 0 or max_size > FirebaseStorage.MAX_DOWNLOAD:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "max_size must be in 1..%d" % FirebaseStorage.MAX_DOWNLOAD)
		return id
	if _fail_if_requested(id) or _fail_if_missing(id, path):
		return id
	var bytes: PackedByteArray = files[path].bytes
	if bytes.size() > max_size:
		_finish_error(id, DOWNLOAD_SIZE_EXCEEDED, "file is larger than max_size")
	else:
		_transfer(id, bytes.size(), _finish.bind(id, bytes.duplicate()))
	return id


func download_file(path: String, local_path: String) -> int:
	var id := _take_id()
	if not (_fail_if_requested(id) or _fail_if_missing(id, path)):
		var bytes: PackedByteArray = files[path].bytes
		_transfer(id, bytes.size(), _write_file.bind(id, local_path, bytes))
	return id


func get_transfer_progress(id: int) -> Dictionary:
	return _transfers.get(id, {}).duplicate()


func cancel_transfer(id: int) -> void:
	if _transfers.erase(id):
		_finish_error(id, CANCELLED, "User cancelled the operation.")


func get_download_url(path: String) -> int:
	var id := _take_id()
	if not (_fail_if_requested(id) or _fail_if_missing(id, path)):
		_finish(id, "https://storage.mock/%s" % path.uri_encode())
	return id


func get_metadata(path: String) -> int:
	var id := _take_id()
	if not (_fail_if_requested(id) or _fail_if_missing(id, path)):
		_finish(id, _metadata(path))
	return id


func update_metadata(path: String, metadata: Dictionary) -> int:
	var id := _take_id()
	var reason := FirebaseStorage.validate_metadata(metadata)
	if not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not (_fail_if_requested(id) or _fail_if_missing(id, path)):
		var file: Dictionary = files[path]
		for key in ["content_type", "cache_control"]:
			if metadata.has(key):
				file[key] = metadata[key]
		var custom: Dictionary = metadata.get("custom_metadata", {})
		var stored: Dictionary = file.get_or_add("custom_metadata", {})
		for key in custom:
			stored[str(key)] = custom[key]
		file.updated = _now_ms()
		_finish(id, _metadata(path))
	return id


func delete_file(path: String) -> int:
	var id := _take_id()
	if not (_fail_if_requested(id) or _fail_if_missing(id, path)):
		files.erase(path)
		_finish(id)
	return id


func list_files(path: String, max_results: int, page_token: String) -> int:
	var id := _take_id()
	if max_results <= 0 or max_results > FirebaseStorage.MAX_LIST_RESULTS:
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "max_results must be in 1..%d" % FirebaseStorage.MAX_LIST_RESULTS)
	elif not _fail_if_requested(id):
		_finish(id, _list(path, max_results, page_token.to_int()))
	return id


## Stores the upload once it finishes; a new upload replaces all metadata.
func _upload(id: int, path: String, data: PackedByteArray, content_type: String) -> void:
	_transfer(id, data.size(), func() -> void:
		var type := content_type if not content_type.is_empty() else DEFAULT_CONTENT_TYPE
		files[path] = {"bytes": data, "content_type": type, "cache_control": "", "custom_metadata": {}, "updated": _now_ms()}
		_finish(id, _metadata(path)))


## Calls `finish` on the next idle frame unless cancel_transfer(id) comes first.
func _transfer(id: int, size: int, finish: Callable) -> void:
	_transfers[id] = {"bytes_transferred": 0, "total_bytes": size}
	_end_transfer.call_deferred(id, finish)


func _end_transfer(id: int, finish: Callable) -> void:
	if _transfers.erase(id):
		finish.call()


func _write_file(id: int, local_path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(local_path, FileAccess.WRITE)
	if file == null:
		_finish_error(id, UNKNOWN, "cannot write %s" % local_path)
		return
	file.store_buffer(bytes)
	file.close()
	_finish(id, bytes.size())


## One list_files() page in name order; its page token is the offset of the next entry.
func _list(folder: String, max_results: int, offset: int) -> Dictionary:
	var children := {}  # Child path -> true for a folder.
	for file_path in files:
		if file_path.begins_with(folder + "/"):
			var rest := file_path.trim_prefix(folder + "/")
			children[folder + "/" + rest.get_slice("/", 0)] = "/" in rest
	var names := children.keys()
	names.sort()
	var found := PackedStringArray()
	var folders := PackedStringArray()
	for child: String in names.slice(offset, offset + max_results):
		if children[child]:
			folders.append(child)
		else:
			found.append(child)
	var next := offset + max_results
	return {"files": found, "folders": folders, "next_page_token": str(next) if next < names.size() else ""}


func _fail_if_missing(id: int, path: String) -> bool:
	if files.has(path):
		return false
	_finish_error(id, OBJECT_NOT_FOUND, "Object does not exist: %s" % path)
	return true


func _metadata(path: String) -> Dictionary:
	var file: Dictionary = files[path]
	var custom: Dictionary = file.get("custom_metadata", {})
	return {"path": path, "name": path.get_file(), "size": file.bytes.size(), "content_type": file.content_type, "cache_control": file.get("cache_control", ""), "custom_metadata": custom.duplicate(), "updated": file.updated}


static func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000)
