#pragma once

#include <firebase/variant.h>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot_firebase {

// Conversion between Godot Variants and firebase::Variant, shared by the
// database and functions modules. Supported values: null, bool, int, finite float,
// String, StringName, Array, packed int, float and string arrays, and
// Dictionary with String keys.
//
// The GDScript layer validates first and reports readable errors; these checks
// repeat its rules so that invalid input never reaches the SDK.

// At most 100 nested containers; active-path cycles are rejected, shared subtrees allowed.
// Returns an empty string on success, otherwise the reason and a null output.
godot::String to_firebase_variant(const godot::Variant &p_value, firebase::Variant &r_out);

// Maps become Dictionary with String keys, vectors become Array, blobs PackedByteArray.
godot::Variant to_godot_variant(const firebase::Variant &p_value);

} // namespace godot_firebase
