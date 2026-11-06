class_name FirebaseFunctions
extends RefCounted
## Cloud Functions (callable HTTPS functions) API.
##
## Data and results are null, bool, int, finite float, String, Array and Dictionary
## with String keys. The region comes from the project setting REGION_SETTING.

const REGION_SETTING := "firebase/functions/region"
const DEFAULT_REGION := "us-central1"

var _requests: FirebaseRequests


func _init(requests: FirebaseRequests) -> void:
	_requests = requests


## Calls the callable function `name`. Result value is its returned data.
func call_function(name: String, data: Variant = null) -> FirebaseTask:
	if not is_valid_name(name):
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, "function name must be non-empty and contain no NUL")
	var reason := validate_data(data)
	if not reason.is_empty():
		return _requests.failed(FirebaseResult.ERR_INVALID_ARGUMENT, reason)
	return _requests.send(&"call_function", [name, data])


## The SDK takes the name as a C string, so NUL would cut it.
static func is_valid_name(name: String) -> bool:
	return not name.is_empty() and not name.to_utf8_buffer().has(0)


## Returns an empty string when `data` can be sent, otherwise the reason.
## Containers may nest at most 100 levels. Shared subtrees are allowed; cycles are not.
static func validate_data(data: Variant) -> String:
	return _validate_data(data, [])


static func _validate_data(data: Variant, ancestors: Array) -> String:
	match typeof(data):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(data) else "numbers must be finite"
		TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if ancestors.size() >= 100:
				return "data exceeds 100 container levels"
			for ancestor in ancestors:
				if is_same(data, ancestor):
					return "data contains a container cycle"
			ancestors.append(data)
			var reason := ""
			for item in data:
				if data is Dictionary:
					if not item is String:
						reason = "keys must be strings: %s" % str(item)
						break
					reason = _validate_data(data[item], ancestors)
				else:
					reason = _validate_data(item, ancestors)
				if not reason.is_empty():
					break
			ancestors.pop_back()
			return reason
	return "unsupported type %s" % type_string(typeof(data))
