#pragma once

#include <firebase/firestore.h>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot_firebase {

// Conversion between Godot Variants and Firestore values. Special values use
// the tagged dictionaries of addons/godot_firebase/firebase_value.gd.
//
// The GDScript layer validates input first and reports readable errors. These
// checks repeat the rules the Firestore SDK enforces by aborting the process,
// so invalid input can never crash the game.

// Returns an empty string on success, otherwise the reason.
// `p_allow_delete` permits delete_field() at the top level (update, merge set).
godot::String to_map_field_value(const godot::Dictionary &p_data, bool p_allow_delete, firebase::firestore::MapFieldValue &r_out);
godot::String to_field_value(const godot::Variant &p_value, firebase::firestore::FieldValue &r_out);

godot::Variant to_variant(const firebase::firestore::FieldValue &p_value);

// {id, path, exists, data}
godot::Dictionary to_snapshot(const firebase::firestore::DocumentSnapshot &p_snapshot);

bool is_document_path(const godot::String &p_path);
bool is_collection_path(const godot::String &p_path);

} // namespace godot_firebase
