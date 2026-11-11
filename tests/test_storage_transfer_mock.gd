extends FirebaseTest

const SOURCE := "user://test_storage_transfer/source.bin"
const TARGET := "user://test_storage_transfer/target.bin"


func _run() -> void:
	var firebase := mock_firebase()
	var storage: FirebaseStorage = firebase.storage
	var bytes := "paket".to_utf8_buffer()
	DirAccess.make_dir_recursive_absolute(SOURCE.get_base_dir())
	FileAccess.open(SOURCE, FileAccess.WRITE).store_buffer(bytes)

	var result := await storage.upload_file("packs/a.pck", SOURCE, "application/octet-stream").wait()
	check(result.ok and result.value.size == bytes.size() and result.value.path == "packs/a.pck", "upload_file returns metadata")
	result = await storage.download_file("packs/a.pck", TARGET).wait()
	check(result.ok and result.value == bytes.size(), "download_file returns the byte count")
	check(FileAccess.get_file_as_bytes(TARGET) == bytes, "download_file writes the stored bytes")
	result = await storage.download_file("packs/a.pck", ProjectSettings.globalize_path(TARGET)).wait()
	check(result.ok, "download_file accepts an absolute path")

	for bad in ["res://a.bin", "a.bin", ""]:
		result = await storage.download_file("packs/a.pck", bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "local path rejected: '%s'" % bad)
	result = await storage.upload_file("packs/b.pck", "user://test_storage_transfer/missing.bin").wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.UNKNOWN, "upload_file of a missing file fails")
	result = await storage.download_file("packs/a.pck", "user://test_storage_transfer/missing/target.bin").wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.UNKNOWN, "download_file into a missing folder fails")
	result = await storage.download_file("packs/missing.pck", TARGET).wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.OBJECT_NOT_FOUND, "download_file of a missing object fails")

	var task := storage.download_bytes("packs/a.pck")
	check(storage.get_transfer_progress(task) == {"bytes_transferred": 0, "total_bytes": bytes.size()}, "running download reports progress")
	storage.cancel_transfer(task)
	result = await task.wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.CANCELLED, "cancelled download fails as cancelled")
	check(storage.get_transfer_progress(task).is_empty(), "finished task has no progress")

	task = storage.upload_bytes("packs/c.pck", bytes)
	storage.cancel_transfer(task)
	result = await task.wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.CANCELLED, "cancelled upload fails as cancelled")
	result = await storage.get_metadata("packs/c.pck").wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.OBJECT_NOT_FOUND, "cancelled upload stores nothing")

	task = storage.download_file("packs/a.pck", TARGET)
	result = await task.wait()
	storage.cancel_transfer(task)
	check(result.ok and task.result.ok, "cancel after the task finished changes nothing")
	task = storage.get_metadata("packs/a.pck")
	check(storage.get_transfer_progress(task).is_empty(), "other requests have no progress")
	await task.wait()

	for path in [SOURCE, TARGET]:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(SOURCE.get_base_dir())
