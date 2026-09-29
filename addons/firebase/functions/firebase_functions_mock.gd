class_name FirebaseFunctionsMock
extends FirebaseMockModule
## In-memory FirebaseFunctionsNative. Register local handlers for functions:
##   Firebase.backends.functions.handlers["add"] = func(data): return data.a + data.b

## firebase::functions::Error code for an unknown function.
const NOT_FOUND := 5

## Function name -> Callable(data) returning the result data.
var handlers: Dictionary[String, Callable] = {}


func call_function(name: String, data: Variant) -> int:
	var id := _take_id()
	if _fail_if_requested(id):
		return id
	if not handlers.has(name):
		_finish_error(id, NOT_FOUND, "No mock handler for function %s" % name)
	else:
		_finish(id, handlers[name].call(data))
	return id
