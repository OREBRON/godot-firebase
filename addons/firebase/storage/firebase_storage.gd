class_name FirebaseStorage
extends RefCounted
## Cloud Storage API.
##
## Metadata results are dictionaries: {path, name, size, content_type,
## cache_control, custom_metadata, updated} where `updated` is Unix time in
## milliseconds and `custom_metadata` has String keys and values.

const DEFAULT_MAX_DOWNLOAD := 10 * 1024 * 1024
## download_bytes() reserves `max_size` bytes up front, so it is capped.
const MAX_DOWNLOAD := 100 * 1024 * 1024
## Largest list_files() page the SDKs accept.
const MAX_LIST_RESULTS := 1000
## Metadata keys update_metadata() can change.
const METADATA_KEYS := ["content_type", "cache_control", "custom_metadata"]

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests


## Result value is the stored file's metadata.
func upload_bytes(path: String, data: PackedByteArray, content_type := "") -> FirebaseTask:
	if content_type.to_utf8_buffer().has(0):
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "content_type must not contain NUL")
	return _file_request(path, &"upload_bytes", [path, data, content_type])


## Uploads the file at `local_path` (user:// or an absolute path) without
## loading it into memory. Result value is the stored file's metadata.
func upload_file(path: String, local_path: String, content_type := "") -> FirebaseTask:
	if content_type.to_utf8_buffer().has(0):
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "content_type must not contain NUL")
	return _local_file_request(path, local_path, &"upload_file", [content_type])


## Result value is a PackedByteArray. Files larger than `max_size` fail.
## `max_size` must be in 1..MAX_DOWNLOAD (100 MB); the whole buffer is reserved before downloading.
## The received bytes are copied from that buffer into the result, so memory
## briefly holds the file at least twice. Use download_file() for large files.
func download_bytes(path: String, max_size := DEFAULT_MAX_DOWNLOAD) -> FirebaseTask:
	if max_size <= 0 or max_size > MAX_DOWNLOAD:
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "max_size must be in 1..%d" % MAX_DOWNLOAD)
	return _file_request(path, &"download_bytes", [path, max_size])


## Writes the file to `local_path` (user:// or an absolute path) instead of
## memory and replaces a file there. Its folder must exist. Result value is the
## number of bytes written; after a failure the local file may be incomplete.
func download_file(path: String, local_path: String) -> FirebaseTask:
	return _local_file_request(path, local_path, &"download_file")


## {bytes_transferred, total_bytes} of a running upload or download task;
## total_bytes is -1 while unknown. Empty once the task finished.
func get_transfer_progress(task: FirebaseTask) -> Dictionary:
	var id := _requests.id_of(task)
	return _requests.backend.get_transfer_progress(id) if id != 0 else {}


## Stops a running upload or download task; it fails with error_code 11
## (cancelled). Does nothing once the task finished.
func cancel_transfer(task: FirebaseTask) -> void:
	var id := _requests.id_of(task)
	if id != 0:
		_requests.backend.cancel_transfer(id)


## Result value is an https URL String.
func get_download_url(path: String) -> FirebaseTask:
	return _file_request(path, &"get_download_url", [path])


func get_metadata(path: String) -> FirebaseTask:
	return _file_request(path, &"get_metadata", [path])


## Changes the METADATA_KEYS given in `metadata` and keeps the others;
## custom_metadata entries are added to the stored ones. Result value is the
## updated metadata.
func update_metadata(path: String, metadata: Dictionary) -> FirebaseTask:
	var reason := validate_metadata(metadata)
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _file_request(path, &"update_metadata", [path, metadata])


func delete_file(path: String) -> FirebaseTask:
	return _file_request(path, &"delete_file", [path])


## Lists the files and folders directly inside the folder at `path` (same rule
## as a file path), up to `max_results` (1..MAX_LIST_RESULTS) per page.
## Result value is {files: PackedStringArray, folders: PackedStringArray,
## next_page_token: String} with full paths; pass next_page_token back for the
## next page. It is "" on the last page.
func list_files(path: String, max_results := MAX_LIST_RESULTS, page_token := "") -> FirebaseTask:
	if max_results <= 0 or max_results > MAX_LIST_RESULTS:
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "max_results must be in 1..%d" % MAX_LIST_RESULTS)
	return _file_request(path, &"list_files", [path, max_results, page_token])


static func is_file_path(path: String) -> bool:
	return not path.is_empty() and not path.begins_with("/") and not path.ends_with("/") and not "//" in path


static func validate_metadata(metadata: Dictionary) -> String:
	for key: Variant in metadata:
		if key not in METADATA_KEYS:
			return "metadata keys are content_type, cache_control and custom_metadata"
	if not metadata.get("content_type", "") is String or not metadata.get("cache_control", "") is String:
		return "content_type and cache_control must be Strings"
	var custom: Variant = metadata.get("custom_metadata", {})
	if not custom is Dictionary:
		return "custom_metadata must be a Dictionary"
	for key: Variant in custom:
		if not (key is String or key is StringName) or not custom[key] is String:
			return "custom_metadata keys and values must be strings"
	return ""


func _file_request(path: String, method: StringName, args: Array) -> FirebaseTask:
	if not is_file_path(path):
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "not a storage file path: %s" % path)
	return _requests.send(method, args)


## Sends the absolute OS path of `local_path`. res:// is not a real file in an exported game.
func _local_file_request(path: String, local_path: String, method: StringName, args: Array = []) -> FirebaseTask:
	var os_path := ProjectSettings.globalize_path(local_path)
	if local_path.begins_with("res://") or "://" in os_path or not os_path.is_absolute_path():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "local_path must be user:// or absolute: %s" % local_path)
	return _file_request(path, method, [path, os_path] + args)
