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
	var backend: FirebaseFunctionsMock = firebase.backends.functions
	var id := backend.call_function("", null)
	var answer: Array = await backend.request_completed
	check(answer[0] == id and not answer[1] and answer[3] == FirebaseResult.ERR_INVALID_ARGUMENT, "mock backend rejects empty name like native")
	result = await functions.call_function("add", {"v": Vector2.ONE}).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "unsupported data rejected")

	var calls := [0]
	firebase.backends.functions.handlers["inspect"] = func(_data):
		calls[0] += 1
		return true
	var cyclic: Array = []
	cyclic.append(cyclic)
	result = await functions.call_function("inspect", cyclic).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "cyclic array rejected")
	check(calls[0] == 0, "cyclic input never calls handler")
	cyclic.clear()

	var indirect: Array = []
	var link := {"child": indirect}
	indirect.append(link)
	result = await functions.call_function("inspect", indirect).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "indirect array dictionary cycle rejected")
	indirect.clear()
	link.clear()

	var shared := {"value": 7}
	result = await functions.call_function("inspect", [shared, shared]).wait()
	check(result.ok, "shared subtree is not a cycle")
	var deep: Variant = 1
	for _i in 100:
		deep = [deep]
	result = await functions.call_function("inspect", deep).wait()
	check(result.ok, "100 containers accepted")
	result = await functions.call_function("inspect", [deep]).wait()
	check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "101 containers rejected")

	calls[0] = 0
	for bad in [NAN, INF, -INF]:
		for data in [bad, {"v": bad}, [bad], PackedFloat64Array([bad]), PackedFloat32Array([bad])]:
			result = await functions.call_function("inspect", data).wait()
			check(not result.ok and result.error_code == FirebaseResult.ERR_INVALID_ARGUMENT, "non-finite number rejected: %s" % str(data))
	check(calls[0] == 0, "non-finite input never calls handler")
	result = await functions.call_function("inspect", {"v": 1.5}).wait()
	check(result.ok, "finite float accepted")
