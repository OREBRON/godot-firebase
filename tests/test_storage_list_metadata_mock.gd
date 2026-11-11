extends FirebaseTest


func _run() -> void:
	var firebase := mock_firebase()
	var storage: FirebaseStorage = firebase.storage
	var bytes := PackedByteArray([1, 2, 3])
	for path in ["packs/b.pck", "packs/a.pck", "packs/levels/1.pck", "packs/levels/2.pck", "other/c.pck"]:
		await storage.upload_bytes(path, bytes).wait()

	var result := await storage.list_files("packs").wait()
	check(result.ok and result.value.files == PackedStringArray(["packs/a.pck", "packs/b.pck"]), "list_files returns direct files in order")
	check(result.value.folders == PackedStringArray(["packs/levels"]) and result.value.next_page_token == "", "list_files returns folders and no next page")
	result = await storage.list_files("packs/levels").wait()
	check(result.ok and result.value.files == PackedStringArray(["packs/levels/1.pck", "packs/levels/2.pck"]), "listed folder paths list again")
	result = await storage.list_files("empty").wait()
	check(result.ok and result.value.files.is_empty() and result.value.folders.is_empty(), "empty folder lists nothing")

	result = await storage.list_files("packs", 2).wait()
	check(result.ok and result.value.files == PackedStringArray(["packs/a.pck", "packs/b.pck"]) and result.value.folders.is_empty(), "first page holds max_results entries")
	result = await storage.list_files("packs", 2, result.value.next_page_token).wait()
	check(result.ok and result.value.folders == PackedStringArray(["packs/levels"]) and result.value.next_page_token == "", "next page continues after the token")
	for bad: int in [0, FirebaseStorage.MAX_LIST_RESULTS + 1]:
		result = await storage.list_files("packs", bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "max_results rejected: %d" % bad)
	result = await storage.list_files("packs/").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "folder path follows the file path rule")

	result = await storage.get_metadata("packs/a.pck").wait()
	check(result.ok and result.value.cache_control == "" and result.value.custom_metadata == {}, "new upload has no cache control or custom metadata")
	result = await storage.update_metadata("packs/a.pck", {"cache_control": "public, max-age=60", "custom_metadata": {version = "2"}}).wait()
	check(result.ok and result.value.cache_control == "public, max-age=60" and result.value.custom_metadata == {"version": "2"}, "update_metadata returns the new metadata")
	check(result.value.content_type == FirebaseStorageMock.DEFAULT_CONTENT_TYPE, "update_metadata keeps keys it was not given")
	result = await storage.update_metadata("packs/a.pck", {"content_type": "application/zip", "custom_metadata": {"author": "ada"}}).wait()
	check(result.ok and result.value.content_type == "application/zip" and result.value.cache_control == "public, max-age=60", "update_metadata changes only given keys")
	check(result.value.custom_metadata == {"version": "2", "author": "ada"}, "custom_metadata entries are added to stored ones")
	result = await storage.get_metadata("packs/a.pck").wait()
	check(result.ok and result.value.custom_metadata == {"version": "2", "author": "ada"}, "get_metadata reads the update")
	result.value.custom_metadata.clear()
	result = await storage.get_metadata("packs/a.pck").wait()
	check(result.value.custom_metadata.size() == 2, "metadata results are copies")

	result = await storage.update_metadata("packs/missing.pck", {"content_type": "text/plain"}).wait()
	check(not result.ok and result.error_code == FirebaseStorageMock.OBJECT_NOT_FOUND, "update_metadata of a missing object fails")
	for bad: Dictionary in [{"size": 1}, {"content_type": 1}, {"cache_control": null}, {"custom_metadata": []}, {"custom_metadata": {"a": 1}}, {"custom_metadata": {1: "a"}}]:
		result = await storage.update_metadata("packs/a.pck", bad).wait()
		check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "metadata rejected: %s" % bad)
