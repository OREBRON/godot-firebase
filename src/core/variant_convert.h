#pragma once

#include <firebase/variant.h>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot_firebase {

// Conversion between Godot Variants and firebase::Variant, shared by the
// database and functions modules. Supported values: null, bool, int, float,
// String, StringName, Array, packed int, float and string arrays, and
// Dictionary with String keys.
//
// The GDScript layer validates first and reports readable errors; these checks
// repeat its rules so that invalid input never reaches the SDK.

// Returns an empty string on success, otherwise the reason.
godot::String to_firebase_variant(const godot::Variant &p_value, firebase::Variant &r_out);

// Maps become Dictionary with String keys, vectors become Array, blobs PackedByteArray.
godot::Variant to_godot_variant(const firebase::Variant &p_value);

} // namespace godot_firebase
