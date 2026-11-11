class_name FirebaseFunctionsMock
extends FirebaseMockModule
## In-memory FirebaseFunctionsNative. Register local handlers for functions:
##   Firebase.backends.functions.handlers["add"] = func(data): return data.a + data.b
## Data and results cross JSON as on a device. A handler gets its own copy in
## which every number is a float, as a JavaScript function sees it; the caller
## gets whole numbers in the int64 range back as int, packed arrays as Array,
## StringName as String and Dictionary keys in sorted order.

## firebase::functions::Error codes: unknown function, and a result the server cannot encode.
const NOT_FOUND := 5
const INTERNAL := 13

## 2^63: whole JSON numbers below this magnitude decode as int on the device.
const _INT64_LIMIT := 9223372036854775808.0

## Function name -> Callable(data) returning the result data.
var handlers: Dictionary[String, Callable] = {}
## Test-observable startup option; the mock never connects to an emulator.
var emulator_host := ""


func initialize(emulator_host: String = "") -> int:
	self.emulator_host = emulator_host
	return OK


func call_function(name: String, data: Variant) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	var reason := FirebaseFunctions.validate_data(data)
	if not FirebaseFunctions.is_valid_name(name):
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, "function name must be non-empty and contain no NUL")
	elif not reason.is_empty():
		_finish_error(id, FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	elif not handlers.has(name):
		_finish_error(id, NOT_FOUND, "No mock handler for function %s" % name)
	else:
		_finish_result(id, handlers[name].call(_through_json(data, false)))
	return id


func _finish_result(id: int, result: Variant) -> void:
	var reason := FirebaseFunctions.validate_data(result)
	if reason.is_empty():
		_finish(id, _through_json(result, true))
	else:
		_finish_error(id, INTERNAL, "Function result cannot be encoded in JSON: %s" % reason)


## Returns a new copy of valid data as it reads after a JSON hop. Every number
## is a double on the wire; `to_device` decodes whole ones in int64 range as int.
static func _through_json(value: Variant, to_device: bool) -> Variant:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			var number := float(value)
			var whole := number == floorf(number) and number >= -_INT64_LIMIT and number < _INT64_LIMIT
			return int(number) if to_device and whole else number
		TYPE_STRING_NAME:
			return String(value)
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var object := {}
			for key in keys:
				object[key] = _through_json(value[key], to_device)
			return object
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var items := []
			for item in value:
				items.append(_through_json(item, to_device))
			return items
	return value
