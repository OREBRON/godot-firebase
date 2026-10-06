extends FirebaseTest


func _run() -> void:
	var firebase := mock_firebase()
	var storage: FirebaseStorage = firebase.storage
	var bytes := "kayıt".to_utf8_buffer()

	var result := await storage.upload_bytes("users/u1/save.json", bytes, "application/json").wait()
	check(result.ok and result.value.size == bytes.size() and result.value.name == "save.json", "upload returns metadata")
	check(result.value.content_type == "application/json", "upload keeps content type")

	result = await storage.download_bytes("users/u1/save.json").wait()
	check(result.ok and result.value == bytes, "download returns uploaded bytes")
	result = await storage.download_bytes("users/u1/save.json", 2).wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.DOWNLOAD_SIZE_EXCEEDED, "download respects max_size")

	result = await storage.get_download_url("users/u1/save.json").wait()
	check(result.ok and result.value.begins_with("https://"), "download url is https")
	result = await storage.get_metadata("users/u1/save.json").wait()
	check(result.ok and result.value.path == "users/u1/save.json", "metadata has path")

	result = await storage.delete_file("users/u1/save.json").wait()
	check(result.ok, "delete succeeds")
	result = await storage.download_bytes("users/u1/save.json").wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.OBJECT_NOT_FOUND, "deleted file is gone")

	for bad in ["", "/abs", "dir/", "a//b"]:
		result = await storage.get_metadata(bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "invalid path rejected: '%s'" % bad)
	result = await storage.download_bytes("a", 0).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "max_size must be positive")
	result = await storage.download_bytes("a", FirebaseStorage.MAX_DOWNLOAD + 1).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "max_size above MAX_DOWNLOAD rejected")
	await storage.upload_bytes("users/u1/limit.bin", bytes).wait()
	result = await storage.download_bytes("users/u1/limit.bin", FirebaseStorage.MAX_DOWNLOAD).wait()
	check(result.ok and result.value == bytes, "max_size equal to MAX_DOWNLOAD accepted")
