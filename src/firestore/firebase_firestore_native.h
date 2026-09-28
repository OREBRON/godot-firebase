#pragma once

#include <unordered_map>

#include <firebase/firestore.h>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Cloud Firestore. Method names and argument shapes match
// addons/godot_firebase/firestore/firebase_firestore_mock.gd.
// Documents are returned as snapshots: {id, path, exists, data}.
class FirebaseFirestoreNative : public FirebaseModuleNative {
	GDCLASS(FirebaseFirestoreNative, FirebaseModuleNative)

public:
	~FirebaseFirestoreNative() override;

	godot::Error initialize();
	int64_t get_doc(const godot::String &p_path);
	int64_t set_doc(const godot::String &p_path, const godot::Dictionary &p_data, bool p_merge);
	int64_t update_doc(const godot::String &p_path, const godot::Dictionary &p_data);
	int64_t delete_doc(const godot::String &p_path);
	int64_t run_query(const godot::String &p_collection, const godot::Array &p_filters, const godot::Array &p_order_by, int64_t p_limit);
	// Ops: {op = "set", path, data, merge} | {op = "update", path, data} | {op = "delete", path}.
	int64_t commit_batch(const godot::Array &p_ops);
	// Emits document_changed(listener_id, ok, snapshot, error_code, error_message).
	int64_t listen_doc(const godot::String &p_path);
	void remove_listener(int64_t p_id);

#ifdef DEBUG_ENABLED
	// Converts `p_data` to Firestore values and back, for tests of value_convert.
	static godot::Dictionary debug_roundtrip(const godot::Dictionary &p_data);
#endif

protected:
	static void _bind_methods();

private:
	// Runs `p_request` with the document at `p_path`, or fails for an invalid path.
	int64_t start_with_document(const godot::String &p_path, const std::function<void(firebase::firestore::DocumentReference, Completion)> &p_request);

	firebase::firestore::Firestore *db = nullptr;
	std::unordered_map<int64_t, firebase::firestore::ListenerRegistration> listeners;
	int64_t next_listener_id = 0;
};

} // namespace godot_firebase
