extends FirebaseTest


func _run() -> void:
	var firebase := mock_firebase()
	var functions: FirebaseFunctions = firebase.functions
	firebase.backends.functions.handlers["add"] = func(data): return {"sum": data.a + data.b}

	var result := await functions.call_function("add", {"a": 2, "b": 3}).wait()
	check(result.ok and result.value == {"sum": 5}, "handler result is returned")

	result = await functions.call_function("missing").wait()
	check(not result.ok and result.error_code == FirebaseFunctionsMock.NOT_FOUND, "unknown function fails")
	result = await functions.call_function("").wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "empty name rejected")
	result = await functions.call_function("add", {"v": Vector2.ONE}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "unsupported data rejected")
