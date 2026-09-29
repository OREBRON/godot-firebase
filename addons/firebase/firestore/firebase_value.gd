class_name FirebaseValue
extends RefCounted
## Firestore values that plain Variants cannot express, plus input validation.
##
## Special values are dictionaries tagged with TAG. The native converter in
## src/value_convert.cpp reads and writes the same tags.

const TAG := "__firebase__"
const TIMESTAMP := "timestamp"
const SERVER_TIMESTAMP := "server_timestamp"
const INCREMENT := "increment"
const DELETE := "delete"
const MAX_IN_VALUES := 30


static func timestamp(unix_seconds: float) -> Dictionary:
	var seconds := floori(unix_seconds)
	return {TAG: TIMESTAMP, "seconds": seconds, "nanos": int((unix_seconds - seconds) * 1e9)}


static func to_unix_seconds(value: Dictionary) -> float:
	return float(value.get("seconds", 0)) + float(value.get("nanos", 0)) / 1e9


static func server_timestamp() -> Dictionary:
	return {TAG: SERVER_TIMESTAMP}


static func increment(by: Variant) -> Dictionary:
	return {TAG: INCREMENT, "by": by}


static func delete_field() -> Dictionary:
	return {TAG: DELETE}


static func tag_of(value: Variant) -> String:
	return value.get(TAG, "") if value is Dictionary else ""


static func is_document_path(path: String) -> bool:
	var count := _segment_count(path)
	return count > 0 and count % 2 == 0


static func is_collection_path(path: String) -> bool:
	return _segment_count(path) % 2 == 1


## Returns an empty string when `data` can be written, otherwise the reason.
## `allow_delete` is true for update and merge writes.
static func validate_data(data: Dictionary, allow_delete: bool) -> String:
	return _validate_map(data, "" if allow_delete else "delete_field() needs update_doc() or set_doc(merge = true)")


## `delete_reason` is empty when delete_field() is allowed in this map.
static func _validate_map(data: Dictionary, delete_reason: String) -> String:
	for key in data:
		if not key is String or key.is_empty() or key.split(".").has(""):
			return "field names must be non-empty strings: %s" % str(key)
		var value: Variant = data[key]
		var reason := delete_reason if tag_of(value) == DELETE else _validate_value(value, false)
		if not reason.is_empty():
			return "%s: %s" % [key, reason]
	return ""


static func validate_filter_value(op: String, value: Variant) -> String:
	if op == "in":
		if not value is Array or value.is_empty() or value.size() > MAX_IN_VALUES:
			return "'in' needs an array with 1-%d values" % MAX_IN_VALUES
		for item in value:
			var item_reason := _validate_value(item, true)
			if not item_reason.is_empty():
				return item_reason
		return ""
	return _validate_value(value, false)


static func _validate_value(value: Variant, in_array: bool) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_PACKED_BYTE_ARRAY:
			return ""
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return "arrays cannot contain arrays" if in_array else ""
		TYPE_ARRAY:
			if in_array:
				return "arrays cannot contain arrays"
			for item in value:
				var item_reason := _validate_value(item, true)
				if not item_reason.is_empty():
					return item_reason
			return ""
		TYPE_DICTIONARY:
			return _validate_dictionary(value, in_array)
	return "unsupported type %s" % type_string(typeof(value))


static func _validate_dictionary(value: Dictionary, in_array: bool) -> String:
	match tag_of(value):
		"":
			return _validate_map(value, "delete_field() must be a top-level field")
		TIMESTAMP:
			var nanos: Variant = value.get("nanos", 0)
			return "" if value.get("seconds") is int and nanos is int and nanos >= 0 and nanos < 1000000000 else "timestamp needs int seconds and nanos in 0..999999999"
		SERVER_TIMESTAMP:
			return "server_timestamp() cannot be inside an array" if in_array else ""
		INCREMENT:
			if in_array:
				return "increment() cannot be inside an array"
			return "" if value.get("by") is int or value.get("by") is float else "increment() needs a number"
		DELETE:
			return "delete_field() cannot be inside an array"
	return "unknown %s tag: %s" % [TAG, tag_of(value)]


static func _segment_count(path: String) -> int:
	if path.is_empty():
		return 0
	var segments := path.split("/")
	return 0 if segments.has("") else segments.size()
