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
# Firestore maps/arrays add at most 20 field levels (document root is level 0).
const MAX_FIELD_DEPTH := 20
# firebase::Timestamp only holds 0001-01-01 .. 9999-12-31.
const MIN_TIMESTAMP_SECONDS := -62135596800
const MAX_TIMESTAMP_SECONDS := 253402300799
const IN_ARRAY := "cannot be inside an array"
const IN_QUERY := "cannot be used in a query"


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


## Returns "" for untagged values and the type name for a tag that is not a string.
static func tag_of(value: Variant) -> String:
	if not value is Dictionary or not value.has(TAG):
		return ""
	var tag: Variant = value[TAG]
	return String(tag) if tag is String or tag is StringName else type_string(typeof(tag))


static func is_document_path(path: String) -> bool:
	var count := _segment_count(path)
	return count > 0 and count % 2 == 0


static func is_collection_path(path: String) -> bool:
	return _segment_count(path) % 2 == 1


## True for a dotted field path the Firestore SDK accepts in queries and update keys.
static func is_field_path(path: Variant) -> bool:
	if not (path is String or path is StringName):
		return false
	var text := String(path)
	if text.is_empty() or text.split(".").has(""):
		return false
	for forbidden in "~*/[]":
		if text.contains(forbidden):
			return false
	return true


## Returns an empty string when `data` can be written, otherwise the reason.
## `allow_delete` is true for update and merge writes.
static func validate_data(data: Dictionary, allow_delete: bool) -> String:
	var reason := _validate_structure(data, [], 0, true)
	if not reason.is_empty():
		return reason
	return _validate_map(data, "" if allow_delete else "delete_field() needs update_doc() or set_doc(merge = true)", "")


## Like validate_data() for update_doc(), whose keys are field paths.
static func validate_update_data(data: Dictionary) -> String:
	for key in data:
		if not is_field_path(key):
			return "update keys must be field paths without ~*/[]: %s" % str(key)
	return validate_data(data, true)


## `delete_reason` is empty when delete_field() is allowed in this map.
## `sentinel_reason` is empty when server_timestamp() and increment() are allowed.
static func _validate_map(data: Dictionary, delete_reason: String, sentinel_reason: String) -> String:
	for key in data:
		if not key is String or key.is_empty() or key.split(".").has(""):
			return "field names must be non-empty strings: %s" % str(key)
		var value: Variant = data[key]
		var reason := delete_reason if tag_of(value) == DELETE else _validate_value(value, false, sentinel_reason)
		if not reason.is_empty():
			return "%s: %s" % [key, reason]
	return ""


static func validate_filter_value(op: String, value: Variant) -> String:
	if op == "in":
		if not value is Array or value.is_empty() or value.size() > MAX_IN_VALUES:
			return "'in' needs an array with 1-%d values" % MAX_IN_VALUES
		for item in value:
			var item_reason := _validate_structure(item, [], 1)
			if item_reason.is_empty():
				item_reason = _validate_value(item, true, IN_QUERY)
			if not item_reason.is_empty():
				return item_reason
		return ""
	var reason := _validate_structure(value, [], 1)
	return _validate_value(value, false, IN_QUERY) if reason.is_empty() else reason


## An active-path guard also permits shared subtrees. Tagged values are scalars.
static func _validate_structure(value: Variant, ancestors: Array, depth: int, document_root: bool = false) -> String:
	if not value is Dictionary and not value is Array:
		if typeof(value) >= TYPE_PACKED_INT32_ARRAY and typeof(value) <= TYPE_PACKED_STRING_ARRAY and depth > MAX_FIELD_DEPTH:
			return "data exceeds 20 map/array field levels"
		return ""
	if value is Dictionary and value.has(TAG) and not document_root:
		return ""
	if depth > MAX_FIELD_DEPTH:
		return "data exceeds 20 map/array field levels"
	for ancestor in ancestors:
		if is_same(value, ancestor):
			return "data contains a container cycle"
	ancestors.append(value)
	var reason := ""
	for key in value:
		reason = _validate_structure(value[key] if value is Dictionary else key, ancestors, depth + 1)
		if not reason.is_empty():
			break
	ancestors.pop_back()
	return reason


static func _validate_value(value: Variant, in_array: bool, sentinel_reason: String) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_PACKED_BYTE_ARRAY:
			return ""
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return "arrays cannot contain arrays" if in_array else ""
		TYPE_ARRAY:
			if in_array:
				return "arrays cannot contain arrays"
			for item in value:
				var item_reason := _validate_value(item, true, IN_ARRAY if sentinel_reason.is_empty() else sentinel_reason)
				if not item_reason.is_empty():
					return item_reason
			return ""
		TYPE_DICTIONARY:
			return _validate_dictionary(value, sentinel_reason)
	return "unsupported type %s" % type_string(typeof(value))


## `sentinel_reason` is empty when server_timestamp() and increment() are allowed.
static func _validate_dictionary(value: Dictionary, sentinel_reason: String) -> String:
	if not value.has(TAG):
		return _validate_map(value, "delete_field() must be a top-level field", sentinel_reason)
	match tag_of(value):
		TIMESTAMP:
			var seconds: Variant = value.get("seconds")
			var nanos: Variant = value.get("nanos", 0)
			if seconds is int and nanos is int and seconds >= MIN_TIMESTAMP_SECONDS and seconds <= MAX_TIMESTAMP_SECONDS and nanos >= 0 and nanos < 1000000000:
				return ""
			return "timestamp needs int seconds in %d..%d and nanos in 0..999999999" % [MIN_TIMESTAMP_SECONDS, MAX_TIMESTAMP_SECONDS]
		SERVER_TIMESTAMP:
			return "" if sentinel_reason.is_empty() else "server_timestamp() " + sentinel_reason
		INCREMENT:
			if not sentinel_reason.is_empty():
				return "increment() " + sentinel_reason
			return "" if value.get("by") is int or value.get("by") is float else "increment() needs a number"
		DELETE:
			return "delete_field() " + (sentinel_reason if not sentinel_reason.is_empty() else "must be a top-level field")
	return "unknown %s tag: %s" % [TAG, tag_of(value)]


static func _segment_count(path: String) -> int:
	if path.is_empty():
		return 0
	var segments := path.split("/")
	return 0 if segments.has("") else segments.size()
