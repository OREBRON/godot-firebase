class_name FirebaseFunctions
extends RefCounted
## Cloud Functions (callable HTTPS functions) API.
##
## Data and results are null, bool, int, float, String, Array and Dictionary
## with String keys. The region comes from the project setting REGION_SETTING.

const REGION_SETTING := "firebase/functions/region"
const DEFAULT_REGION := "us-central1"

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests


## Calls the callable function `name`. Result value is its returned data.
func call_function(name: String, data: Variant = null) -> FirebaseTask:
	if name.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "function name must not be empty")
	var reason := validate_data(data)
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _requests.send(&"call_function", [name, data])


## Returns an empty string when `data` can be sent, otherwise the reason.
static func validate_data(data: Variant) -> String:
	match typeof(data):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			for item in data:
				var reason := validate_data(item)
				if not reason.is_empty():
					return reason
			return ""
		TYPE_DICTIONARY:
			for key in data:
				if not key is String:
					return "keys must be strings: %s" % str(key)
				var reason := validate_data(data[key])
				if not reason.is_empty():
					return reason
			return ""
	return "unsupported type %s" % type_string(typeof(data))
