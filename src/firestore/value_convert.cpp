#include "value_convert.h"

#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "../core/outcome.h"

using firebase::firestore::DocumentSnapshot;
using firebase::firestore::FieldValue;
using firebase::firestore::Firestore;
using firebase::firestore::MapFieldValue;
using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

// Tags of addons/firebase/firestore/firebase_value.gd.
const char *const kTag = "__firebase__";
const char *const kTimestamp = "timestamp";
const char *const kServerTimestamp = "server_timestamp";
const char *const kIncrement = "increment";
const char *const kDelete = "delete";
const char *const kGeoPoint = "geo_point";
const char *const kReference = "reference";
const char *const kArrayUnion = "array_union";
const char *const kArrayRemove = "array_remove";

// Reasons server_timestamp(), increment() and delete_field() are not allowed.
const char *const kInArray = "cannot be inside an array";
const char *const kInQuery = "cannot be used in a query";

// firebase::Timestamp aborts outside 0001-01-01 .. 9999-12-31.
constexpr int64_t kMinSeconds = -62135596800;
constexpr int64_t kMaxSeconds = 253402300799;
constexpr int64_t kNanosPerSecond = 1000000000;

bool is_string(const Variant &p_value) {
	return p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME;
}

bool is_number(const Variant &p_value) {
	return p_value.get_type() == Variant::INT || p_value.get_type() == Variant::FLOAT;
}

bool is_array_transform(const Dictionary &p_value) {
	const Variant tag = p_value.get(kTag, Variant());
	return is_string(tag) && (String(tag) == kArrayUnion || String(tag) == kArrayRemove);
}

bool is_reserved_segment(const String &p_segment) {
	return p_segment.begins_with("__") && p_segment.ends_with("__");
}

// Same rule as FirebaseValue.is_reserved_field_name(): the SDK aborts when a
// written field name begins and ends with "__". A `p_path` (update key) is
// dotted, so each segment is a field name; other map keys are literal names.
bool is_reserved_field_name(const String &p_name, bool p_path) {
	if (!p_path) {
		return is_reserved_segment(p_name);
	}
	const godot::PackedStringArray segments = p_name.split(".");
	for (int64_t i = 0; i < segments.size(); i++) {
		if (is_reserved_segment(segments[i])) {
			return true;
		}
	}
	return false;
}

// Firestore's published map/array field depth limit. The document root is 0;
// tagged timestamp/transform dictionaries represent scalar FieldValues.
String validate_structure(const Variant &p_value, std::vector<Variant> &p_ancestors, int p_depth, bool p_document_root = false) {
	const Variant::Type type = p_value.get_type();
	if (type != Variant::DICTIONARY && type != Variant::ARRAY) {
		return type >= Variant::PACKED_INT32_ARRAY && type <= Variant::PACKED_STRING_ARRAY && p_depth > 20 ? String("data exceeds 20 map/array field levels") : String();
	}
	if (type == Variant::DICTIONARY && Dictionary(p_value).has(kTag) && !p_document_root) {
		// Array transform elements sit at the level of the field they change.
		const Variant elements = Dictionary(p_value).get("elements", Variant());
		return is_array_transform(p_value) && elements.get_type() == Variant::ARRAY ? validate_structure(elements, p_ancestors, p_depth) : String();
	}
	if (p_depth > 20) {
		return "data exceeds 20 map/array field levels";
	}
	for (const Variant &ancestor : p_ancestors) {
		if (godot::UtilityFunctions::is_same(p_value, ancestor)) {
			return "data contains a container cycle";
		}
	}
	p_ancestors.push_back(p_value);
	String reason;
	if (type == Variant::DICTIONARY) {
		const Dictionary map = p_value;
		const Array keys = map.keys();
		for (int64_t i = 0; i < keys.size(); ++i) {
			reason = validate_structure(map[keys[i]], p_ancestors, p_depth + 1);
			if (!reason.is_empty()) {
				break;
			}
		}
	} else {
		const Array items = p_value;
		for (int64_t i = 0; i < items.size(); ++i) {
			reason = validate_structure(items[i], p_ancestors, p_depth + 1);
			if (!reason.is_empty()) {
				break;
			}
		}
	}
	p_ancestors.pop_back();
	return reason;
}

// `p_sentinel_reason` is null when server_timestamp() and increment() are allowed.
// `p_allow_delete` permits delete_field() in maps nested in `p_value` (merge set).
String convert(Firestore *p_db, const Variant &p_value, bool p_in_array, const char *p_sentinel_reason, bool p_allow_delete, FieldValue &r_out);

// Array items: no nested arrays, and no sentinels.
String convert_items(Firestore *p_db, const Array &p_items, const char *p_sentinel_reason, std::vector<FieldValue> &r_out) {
	r_out.reserve(static_cast<size_t>(p_items.size()));
	for (int64_t i = 0; i < p_items.size(); i++) {
		FieldValue item;
		const String reason = convert(p_db, p_items[i], true, p_sentinel_reason ? p_sentinel_reason : kInArray, false, item);
		if (!reason.is_empty()) {
			return reason;
		}
		r_out.push_back(item);
	}
	return String();
}

String convert_array(Firestore *p_db, const Array &p_items, const char *p_sentinel_reason, FieldValue &r_out) {
	std::vector<FieldValue> values;
	const String reason = convert_items(p_db, p_items, p_sentinel_reason, values);
	if (reason.is_empty()) {
		r_out = FieldValue::Array(std::move(values));
	}
	return reason;
}

// Elements follow the array item rules; the SDK aborts on a sentinel or nested array among them.
String convert_array_transform(Firestore *p_db, const Dictionary &p_value, const String &p_tag, FieldValue &r_out) {
	const Variant elements = p_value.get("elements", Variant());
	if (elements.get_type() != Variant::ARRAY) {
		return p_tag + String(" needs an Array of elements");
	}
	std::vector<FieldValue> values;
	const String reason = convert_items(p_db, elements, nullptr, values);
	if (reason.is_empty()) {
		r_out = p_tag == kArrayUnion ? FieldValue::ArrayUnion(std::move(values)) : FieldValue::ArrayRemove(std::move(values));
	}
	return reason;
}

String convert_timestamp(const Dictionary &p_value, FieldValue &r_out) {
	const Variant seconds = p_value.get("seconds", Variant());
	const Variant nanos = p_value.get("nanos", 0);
	if (seconds.get_type() != Variant::INT || nanos.get_type() != Variant::INT) {
		return "timestamp needs int seconds and nanos";
	}
	const int64_t whole = seconds;
	const int64_t fraction = nanos;
	if (whole < kMinSeconds || whole > kMaxSeconds || fraction < 0 || fraction >= kNanosPerSecond) {
		return "timestamp out of range";
	}
	r_out = FieldValue::Timestamp(firebase::Timestamp(whole, static_cast<int32_t>(fraction)));
	return String();
}

String convert_geo_point(const Dictionary &p_value, FieldValue &r_out) {
	const Variant latitude = p_value.get("latitude", Variant());
	const Variant longitude = p_value.get("longitude", Variant());
	if (!is_number(latitude) || !is_number(longitude)) {
		return "geo_point needs number latitude and longitude";
	}
	const double lat = latitude;
	const double lng = longitude;
	// firebase::firestore::GeoPoint aborts outside these ranges; NaN fails every comparison.
	if (!(lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0)) {
		return "geo_point out of range";
	}
	r_out = FieldValue::GeoPoint(firebase::firestore::GeoPoint(lat, lng));
	return String();
}

String convert_tagged(Firestore *p_db, const Dictionary &p_value, const char *p_sentinel_reason, FieldValue &r_out) {
	const Variant tag_value = p_value[kTag];
	if (!is_string(tag_value)) {
		return "unknown tag of type " + Variant::get_type_name(tag_value.get_type());
	}
	const String tag = tag_value;
	if (tag == kTimestamp) {
		return convert_timestamp(p_value, r_out);
	}
	if (tag == kGeoPoint) {
		return convert_geo_point(p_value, r_out);
	}
	if (tag == kReference) {
		// Firestore::Document() aborts on a path that does not name a document.
		const Variant path = p_value.get("path", Variant());
		if (!is_string(path) || !is_document_path(path)) {
			return "reference needs a document path";
		}
		r_out = FieldValue::Reference(p_db->Document(to_std(path)));
		return String();
	}
	if (p_sentinel_reason && (tag == kServerTimestamp || tag == kIncrement || tag == kDelete || is_array_transform(p_value))) {
		return tag + String(" ") + p_sentinel_reason;
	}
	if (is_array_transform(p_value)) {
		return convert_array_transform(p_db, p_value, tag, r_out);
	}
	if (tag == kServerTimestamp) {
		r_out = FieldValue::ServerTimestamp();
		return String();
	}
	if (tag == kIncrement) {
		const Variant by = p_value.get("by", Variant());
		if (by.get_type() == Variant::INT) {
			r_out = FieldValue::Increment(static_cast<int64_t>(by));
			return String();
		}
		if (by.get_type() == Variant::FLOAT) {
			r_out = FieldValue::Increment(static_cast<double>(by));
			return String();
		}
		return "increment needs a number";
	}
	if (tag == kDelete) {
		return "delete_field() needs a merge set or a top-level update field";
	}
	return "unknown tag " + tag;
}

// Keys are literal field names unless `p_path_keys` (top-level update keys).
String convert_map(Firestore *p_db, const Dictionary &p_data, bool p_allow_delete, const char *p_sentinel_reason, bool p_path_keys, MapFieldValue &r_out) {
	const Array keys = p_data.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		if (!is_string(key)) {
			return "field names must be strings";
		}
		const String name = key;
		if (name.is_empty() || name.split(".").has("")) {
			return "field names must be non-empty: " + name;
		}
		// Query values may use reserved names; written data may not.
		if (p_sentinel_reason != kInQuery && is_reserved_field_name(name, p_path_keys)) {
			return "field names cannot begin and end with __: " + name;
		}
		const Variant value = p_data[key];
		FieldValue field;
		if (p_allow_delete && value.get_type() == Variant::DICTIONARY && String(Dictionary(value).get(kTag, "")) == kDelete) {
			field = FieldValue::Delete();
		} else {
			// The SDK aborts on delete_field() nested in update data; a merge set takes it in nested maps.
			const String reason = convert(p_db, value, false, p_sentinel_reason, p_allow_delete && !p_path_keys, field);
			if (!reason.is_empty()) {
				return name + String(": ") + reason;
			}
		}
		r_out[to_std(name)] = field;
	}
	return String();
}

String convert(Firestore *p_db, const Variant &p_value, bool p_in_array, const char *p_sentinel_reason, bool p_allow_delete, FieldValue &r_out) {
	switch (p_value.get_type()) {
		case Variant::NIL:
			r_out = FieldValue::Null();
			return String();
		case Variant::BOOL:
			r_out = FieldValue::Boolean(p_value);
			return String();
		case Variant::INT:
			r_out = FieldValue::Integer(static_cast<int64_t>(p_value));
			return String();
		case Variant::FLOAT:
			r_out = FieldValue::Double(static_cast<double>(p_value));
			return String();
		case Variant::STRING:
		case Variant::STRING_NAME:
			r_out = FieldValue::String(to_std(p_value));
			return String();
		case Variant::PACKED_BYTE_ARRAY: {
			const godot::PackedByteArray bytes = p_value;
			r_out = FieldValue::Blob(bytes.ptr(), static_cast<size_t>(bytes.size()));
			return String();
		}
		case Variant::ARRAY:
		case Variant::PACKED_INT32_ARRAY:
		case Variant::PACKED_INT64_ARRAY:
		case Variant::PACKED_FLOAT32_ARRAY:
		case Variant::PACKED_FLOAT64_ARRAY:
		case Variant::PACKED_STRING_ARRAY:
			if (p_in_array) {
				return "arrays cannot contain arrays";
			}
			return convert_array(p_db, p_value, p_sentinel_reason, r_out);
		case Variant::DICTIONARY: {
			const Dictionary map = p_value;
			if (map.has(kTag)) {
				return convert_tagged(p_db, map, p_sentinel_reason, r_out);
			}
			MapFieldValue fields;
			const String reason = convert_map(p_db, map, p_allow_delete, p_sentinel_reason, false, fields);
			if (reason.is_empty()) {
				r_out = FieldValue::Map(std::move(fields));
			}
			return reason;
		}
		default:
			return "unsupported type " + Variant::get_type_name(p_value.get_type());
	}
}

int segment_count(const String &p_path) {
	if (p_path.is_empty()) {
		return 0;
	}
	const godot::PackedStringArray segments = p_path.split("/");
	return segments.has("") ? 0 : static_cast<int>(segments.size());
}

// `p_path_keys` is true when the top-level keys are dotted update paths.
String to_document(Firestore *p_db, const Dictionary &p_data, bool p_allow_delete, bool p_path_keys, MapFieldValue &r_out) {
	std::vector<Variant> ancestors;
	const String reason = validate_structure(p_data, ancestors, 0, true);
	return reason.is_empty() ? convert_map(p_db, p_data, p_allow_delete, nullptr, p_path_keys, r_out) : reason;
}

// Containers nested deeper than kMaxIncomingDepth become null.
Variant to_variant(const FieldValue &p_value, int p_depth) {
	switch (p_value.type()) {
		case FieldValue::Type::kBoolean:
			return p_value.boolean_value();
		case FieldValue::Type::kInteger:
			return p_value.integer_value();
		case FieldValue::Type::kDouble:
			return p_value.double_value();
		case FieldValue::Type::kString:
			return to_godot(p_value.string_value());
		case FieldValue::Type::kTimestamp: {
			Dictionary stamp;
			stamp[kTag] = kTimestamp;
			stamp["seconds"] = p_value.timestamp_value().seconds();
			stamp["nanos"] = p_value.timestamp_value().nanoseconds();
			return stamp;
		}
		case FieldValue::Type::kBlob: {
			godot::PackedByteArray bytes;
			if (bytes.resize(static_cast<int64_t>(p_value.blob_size())) != godot::OK) {
				return Variant();
			}
			if (p_value.blob_size() > 0) {
				memcpy(bytes.ptrw(), p_value.blob_value(), p_value.blob_size());
			}
			return bytes;
		}
		case FieldValue::Type::kReference: {
			Dictionary reference;
			reference[kTag] = kReference;
			reference["path"] = to_godot(p_value.reference_value().path());
			return reference;
		}
		case FieldValue::Type::kGeoPoint: {
			Dictionary point;
			point[kTag] = kGeoPoint;
			point["latitude"] = p_value.geo_point_value().latitude();
			point["longitude"] = p_value.geo_point_value().longitude();
			return point;
		}
		case FieldValue::Type::kArray: {
			if (p_depth >= kMaxIncomingDepth) {
				return Variant();
			}
			Array items;
			for (const FieldValue &item : p_value.array_value()) {
				items.push_back(to_variant(item, p_depth + 1));
			}
			return items;
		}
		case FieldValue::Type::kMap: {
			if (p_depth >= kMaxIncomingDepth) {
				return Variant();
			}
			Dictionary map;
			for (const auto &field : p_value.map_value()) {
				String key;
				if (to_godot_key(field.first, key)) {
					map[key] = to_variant(field.second, p_depth + 1);
				}
			}
			return map;
		}
		default:
			// Null and write-only sentinels.
			return Variant();
	}
}

} // namespace

String to_map_field_value(Firestore *p_db, const Dictionary &p_data, bool p_allow_delete, MapFieldValue &r_out) {
	return to_document(p_db, p_data, p_allow_delete, false, r_out);
}

String to_update_field_value(Firestore *p_db, const Dictionary &p_data, MapFieldValue &r_out) {
	const Array keys = p_data.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		if (!is_field_path(keys[i])) {
			return "update keys must be field paths without ~*/[]: " + String(keys[i]);
		}
	}
	return to_document(p_db, p_data, true, true, r_out);
}

String to_query_value(Firestore *p_db, const Variant &p_value, FieldValue &r_out) {
	std::vector<Variant> ancestors;
	const String reason = validate_structure(p_value, ancestors, 1);
	return reason.is_empty() ? convert(p_db, p_value, false, kInQuery, false, r_out) : reason;
}

String to_query_values(Firestore *p_db, const Array &p_items, std::vector<FieldValue> &r_out) {
	for (int64_t i = 0; i < p_items.size(); i++) {
		std::vector<Variant> ancestors;
		const String reason = validate_structure(p_items[i], ancestors, 1);
		if (!reason.is_empty()) {
			return reason;
		}
	}
	return convert_items(p_db, p_items, kInQuery, r_out);
}

Dictionary to_snapshot(const DocumentSnapshot &p_snapshot) {
	Dictionary snapshot;
	snapshot["id"] = to_godot(p_snapshot.id());
	snapshot["path"] = to_godot(p_snapshot.reference().path());
	snapshot["exists"] = p_snapshot.exists();
	Dictionary data;
	if (p_snapshot.exists()) {
		const MapFieldValue fields = p_snapshot.GetData(DocumentSnapshot::ServerTimestampBehavior::kEstimate);
		for (const auto &field : fields) {
			String key;
			if (to_godot_key(field.first, key)) {
				data[key] = to_variant(field.second, 1);
			}
		}
	}
	snapshot["data"] = data;
	snapshot["metadata"] = to_metadata(p_snapshot.metadata());
	return snapshot;
}

Dictionary to_metadata(const firebase::firestore::SnapshotMetadata &p_metadata) {
	Dictionary metadata;
	metadata["is_from_cache"] = p_metadata.is_from_cache();
	metadata["has_pending_writes"] = p_metadata.has_pending_writes();
	return metadata;
}

bool is_document_path(const String &p_path) {
	const int count = segment_count(p_path);
	return count > 0 && count % 2 == 0;
}

bool is_collection_path(const String &p_path) {
	return segment_count(p_path) % 2 == 1;
}

bool is_field_path(const Variant &p_path) {
	if (!is_string(p_path)) {
		return false;
	}
	const String path = p_path;
	if (path.is_empty() || path.split(".").has("")) {
		return false;
	}
	for (const char *forbidden : { "~", "*", "/", "[", "]" }) {
		if (path.contains(forbidden)) {
			return false;
		}
	}
	return true;
}

} // namespace godot_firebase
