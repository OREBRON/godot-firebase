#pragma once

#include <firebase/firestore.h>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot_firebase {

// Conversion between Godot Variants and Firestore values. Special values use
// the tagged dictionaries of addons/firebase/firestore/firebase_value.gd.
//
// The GDScript layer validates input first and reports readable errors. These
// checks repeat the rules the Firestore SDK enforces by aborting the process,
// so invalid input can never crash the game.

// Returns an empty string on success, otherwise the reason. `p_db` builds reference values.
// `p_allow_delete` permits delete_field() at the top level (update, merge set).
godot::String to_map_field_value(firebase::firestore::Firestore *p_db, const godot::Dictionary &p_data, bool p_allow_delete, firebase::firestore::MapFieldValue &r_out);
// Update data: keys are field paths, delete_field() is allowed.
godot::String to_update_field_value(firebase::firestore::Firestore *p_db, const godot::Dictionary &p_data, firebase::firestore::MapFieldValue &r_out);
// A filter value: write-only special values are rejected.
godot::String to_query_value(firebase::firestore::Firestore *p_db, const godot::Variant &p_value, firebase::firestore::FieldValue &r_out);

// {id, path, exists, data, metadata}
godot::Dictionary to_snapshot(const firebase::firestore::DocumentSnapshot &p_snapshot);

godot::Dictionary to_metadata(const firebase::firestore::SnapshotMetadata &p_metadata);

bool is_document_path(const godot::String &p_path);
bool is_collection_path(const godot::String &p_path);
// A dotted field path the SDK accepts: no empty segment and none of ~*/[].
bool is_field_path(const godot::Variant &p_path);

} // namespace godot_firebase
