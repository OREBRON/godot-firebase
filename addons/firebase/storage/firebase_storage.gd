class_name FirebaseStorage
extends RefCounted
## Cloud Storage API.
##
## Metadata results are dictionaries: {path, name, size, content_type, updated}
## where `updated` is Unix time in milliseconds.

const DEFAULT_MAX_DOWNLOAD := 10 * 1024 * 1024
## download_bytes() reserves `max_size` bytes up front, so it is capped.
const MAX_DOWNLOAD := 100 * 1024 * 1024

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests


## Result value is the stored file's metadata.
func upload_bytes(path: String, data: PackedByteArray, content_type := "") -> FirebaseTask:
	if content_type.to_utf8_buffer().has(0):
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "content_type must not contain NUL")
	return _file_request(path, &"upload_bytes", [path, data, content_type])


## Result value is a PackedByteArray. Files larger than `max_size` fail.
## `max_size` must be in 1..MAX_DOWNLOAD (100 MB); the whole buffer is reserved before downloading.
func download_bytes(path: String, max_size := DEFAULT_MAX_DOWNLOAD) -> FirebaseTask:
	if max_size <= 0 or max_size > MAX_DOWNLOAD:
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "max_size must be in 1..%d" % MAX_DOWNLOAD)
	return _file_request(path, &"download_bytes", [path, max_size])


## Result value is an https URL String.
func get_download_url(path: String) -> FirebaseTask:
	return _file_request(path, &"get_download_url", [path])


func get_metadata(path: String) -> FirebaseTask:
	return _file_request(path, &"get_metadata", [path])


func delete_file(path: String) -> FirebaseTask:
	return _file_request(path, &"delete_file", [path])


static func is_file_path(path: String) -> bool:
	return not path.is_empty() and not path.begins_with("/") and not path.ends_with("/") and not "//" in path


func _file_request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not is_file_path(path):
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "not a storage file path: %s" % path)
	return _requests.send(method, args)
