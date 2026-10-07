extends FirebaseTest
## Callable data and results cross JSON like on a device: handlers see
## JavaScript numbers, callers see what the Android/iOS SDKs decode.


func _run() -> void:
	var firebase := mock_firebase()
	var functions: FirebaseFunctions = firebase.functions
	var backend: FirebaseFunctionsMock = firebase.backends.functions
	var received := []
	backend.handlers["echo"] = func(data):
		received.append(data)
		return data

	var sent := {"n": 2, "f": 1.5, "s": &"name", "ints": PackedInt32Array([1, 2]), "words": PackedStringArray(["a"]), "on": true, "none": null, "big": 9007199254740993}
	var result := await functions.call_function("echo", sent).wait()
	var seen: Dictionary = received[0]
	check(typeof(seen.n) == TYPE_FLOAT and seen.n == 2.0 and typeof(seen.ints[0]) == TYPE_FLOAT, "handler sees every number as a float")
	check(typeof(seen.s) == TYPE_STRING and typeof(seen.ints) == TYPE_ARRAY and seen.words == ["a"], "handler sees String and Array")
	check(seen.big == 9007199254740992.0, "int64 beyond 2^53 reaches the server as a double")
	seen.n = 99
	check(sent.n == 2, "handler gets an isolated copy")
	check(result.ok and typeof(result.value.n) == TYPE_INT and result.value.n == 2 and typeof(result.value.f) == TYPE_FLOAT, "whole numbers return as int, fractions as float")
	check(result.value.ints == [1, 2] and typeof(result.value.ints[0]) == TYPE_INT and typeof(result.value.s) == TYPE_STRING, "packed arrays return as Array, StringName as String")
	check(result.value.on == true and result.value.none == null and result.value.big == 9007199254740992, "bool, null and rounded int64 return")
	check(result.value.keys() == ["big", "f", "ints", "n", "none", "on", "s", "words"], "result keys are sorted like the SDK map")

	backend.handlers["half"] = func(data): return data / 2
	result = await functions.call_function("half", 5).wait()
	check(result.ok and result.value == 2.5, "handler arithmetic uses JavaScript numbers")

	var state := {"count": 1}
	backend.handlers["state"] = func(_data): return state
	result = await functions.call_function("state").wait()
	result.value.count = 50
	check(state.count == 1, "caller gets a copy of the result")

	backend.handlers["numbers"] = func(_data): return [4.0, PackedFloat32Array([0.5]), 1e19, -9223372036854775808.0, 9007199254740993]
	result = await functions.call_function("numbers").wait()
	var numbers: Array = result.value
	check(typeof(numbers[0]) == TYPE_INT and numbers[0] == 4 and numbers[1] == [0.5], "whole float result returns as int")
	check(typeof(numbers[2]) == TYPE_FLOAT and numbers[3] == -9223372036854775807 - 1 and numbers[4] == 9007199254740992, "only whole numbers in int64 range return as int")

	var cyclic: Array = []
	cyclic.append(cyclic)
	for bad in [Vector2.ONE, NAN, INF, {"v": -INF}, {1: "x"}, cyclic]:
		backend.handlers["bad"] = func(_data): return bad
		result = await functions.call_function("bad").wait()
		check(not result.ok and result.error_code == FirebaseFunctionsMock.INTERNAL, "unencodable result fails as INTERNAL: %s" % type_string(typeof(bad)))
	cyclic.clear()

	received.clear()
	backend.call_function("echo", Vector2.ONE)
	var completed: Array = await backend.request_completed
	check(not completed[1] and completed[3] == FirebaseResult.ERR_INVALID_ARGUMENT and received.is_empty(), "backend rejects invalid data like native")
