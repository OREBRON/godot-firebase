class_name FirebaseStorageMock
extends FirebaseMockModule
## In-memory FirebaseStorageNative. Nothing is persisted.

## Storage error codes (firebase::storage::Error).
const OBJECT_NOT_FOUND := 2
const DOWNLOAD_SIZE_EXCEEDED := 10

## Path -> {bytes, content_type, updated}
var files: Dictionary[String, Dictionary] = {}


func upload_bytes(path: String, data: PackedByteArray, content_type: String) -> int:
	var id := _take_id()
	if not _fail_if_requested(id):
		files[path] = {"bytes": data.duplicate(), "content_type": content_type, "updated": int(Time.get_unix_time_from_system() * 1000)}
		_finish(id, _metadata(path))
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
		_finish(id, bytes.duplicate())
	return id


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


func delete_file(path: String) -> int:
	var id := _take_id()
	if not (_fail_if_requested(id) or _fail_if_missing(id, path)):
		files.erase(path)
		_finish(id)
	return id


func _fail_if_missing(id: int, path: String) -> bool:
	if files.has(path):
		return false
	_finish_error(id, OBJECT_NOT_FOUND, "Object does not exist: %s" % path)
	return true


func _metadata(path: String) -> Dictionary:
	var file: Dictionary = files[path]
	return {"path": path, "name": path.get_file(), "size": file.bytes.size(), "content_type": file.content_type, "updated": file.updated}
