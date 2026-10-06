#include "variant_convert.h"

#include <cmath>
#include <cstring>
#include <map>
#include <utility>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "outcome.h"

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

String convert_value(const Variant &p_value, firebase::Variant &r_out, std::vector<Variant> &p_ancestors);

String convert_array(const Array &p_items, firebase::Variant &r_out, std::vector<Variant> &p_ancestors) {
	r_out = firebase::Variant::EmptyVector();
	std::vector<firebase::Variant> &items = r_out.vector();
	items.reserve(static_cast<size_t>(p_items.size()));
	for (int64_t i = 0; i < p_items.size(); i++) {
		firebase::Variant item;
		const String reason = convert_value(p_items[i], item, p_ancestors);
		if (!reason.is_empty()) {
			return reason;
		}
		items.push_back(std::move(item));
	}
	return String();
}

String convert_map(const Dictionary &p_map, firebase::Variant &r_out, std::vector<Variant> &p_ancestors) {
	r_out = firebase::Variant::EmptyMap();
	std::map<firebase::Variant, firebase::Variant> &entries = r_out.map();
	const Array keys = p_map.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return "keys must be strings: " + String(key);
		}
		firebase::Variant value;
		const String reason = convert_value(p_map[key], value, p_ancestors);
		if (!reason.is_empty()) {
			return String(key) + ": " + reason;
		}
		entries[firebase::Variant(to_std(key))] = std::move(value);
	}
	return String();
}

String key_to_string(const firebase::Variant &p_key) {
	if (p_key.is_string()) {
		return String::utf8(p_key.string_value());
	}
	return String(to_godot_variant(p_key));
}

String convert_value(const Variant &p_value, firebase::Variant &r_out, std::vector<Variant> &p_ancestors) {
	switch (p_value.get_type()) {
		case Variant::NIL:
			r_out = firebase::Variant::Null();
			return String();
		case Variant::BOOL:
			r_out = firebase::Variant(static_cast<bool>(p_value));
			return String();
		case Variant::INT:
			r_out = firebase::Variant(static_cast<int64_t>(p_value));
			return String();
		case Variant::FLOAT:
			// iOS JSON serialization raises an uncatchable exception for NaN/Inf.
			if (!std::isfinite(static_cast<double>(p_value))) {
				return "numbers must be finite";
			}
			r_out = firebase::Variant(static_cast<double>(p_value));
			return String();
		case Variant::STRING:
		case Variant::STRING_NAME:
			r_out = firebase::Variant(to_std(p_value));
			return String();
		case Variant::ARRAY:
		case Variant::PACKED_INT32_ARRAY:
		case Variant::PACKED_INT64_ARRAY:
		case Variant::PACKED_FLOAT32_ARRAY:
		case Variant::PACKED_FLOAT64_ARRAY:
		case Variant::PACKED_STRING_ARRAY:
		case Variant::DICTIONARY:
			break;
		default:
			return "unsupported type " + Variant::get_type_name(p_value.get_type());
	}
	if (p_ancestors.size() >= 100) {
		return "data exceeds 100 container levels";
	}
	for (const Variant &ancestor : p_ancestors) {
		if (godot::UtilityFunctions::is_same(p_value, ancestor)) {
			return "data contains a container cycle";
		}
	}
	p_ancestors.push_back(p_value);
	const String reason = p_value.get_type() == Variant::DICTIONARY ?
			convert_map(p_value, r_out, p_ancestors) : convert_array(p_value, r_out, p_ancestors);
	p_ancestors.pop_back();
	return reason;
}

} // namespace

String to_firebase_variant(const Variant &p_value, firebase::Variant &r_out) {
	std::vector<Variant> ancestors;
	firebase::Variant converted;
	const String reason = convert_value(p_value, converted, ancestors);
	r_out = reason.is_empty() ? std::move(converted) : firebase::Variant::Null();
	return reason;
}

Variant to_godot_variant(const firebase::Variant &p_value) {
	switch (p_value.type()) {
		case firebase::Variant::kTypeInt64:
			return p_value.int64_value();
		case firebase::Variant::kTypeDouble:
			return p_value.double_value();
		case firebase::Variant::kTypeBool:
			return p_value.bool_value();
		case firebase::Variant::kTypeStaticString:
		case firebase::Variant::kTypeMutableString:
			return String::utf8(p_value.string_value());
		case firebase::Variant::kTypeVector: {
			Array items;
			for (const firebase::Variant &item : p_value.vector()) {
				items.push_back(to_godot_variant(item));
			}
			return items;
		}
		case firebase::Variant::kTypeMap: {
			Dictionary map;
			for (const auto &entry : p_value.map()) {
				map[key_to_string(entry.first)] = to_godot_variant(entry.second);
			}
			return map;
		}
		case firebase::Variant::kTypeStaticBlob:
		case firebase::Variant::kTypeMutableBlob: {
			godot::PackedByteArray bytes;
			bytes.resize(static_cast<int64_t>(p_value.blob_size()));
			if (p_value.blob_size() > 0) {
				memcpy(bytes.ptrw(), p_value.blob_data(), p_value.blob_size());
			}
			return bytes;
		}
		default:
			return Variant();
	}
}

} // namespace godot_firebase
