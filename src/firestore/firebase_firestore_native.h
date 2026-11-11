#pragma once

#include <unordered_map>

#include <firebase/firestore.h>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Cloud Firestore. Method names and argument shapes match
// addons/firebase/firestore/firebase_firestore_mock.gd.
// Documents are returned as snapshots: {id, path, exists, data, metadata}.
class FirebaseFirestoreNative : public FirebaseModuleNative {
	GDCLASS(FirebaseFirestoreNative, FirebaseModuleNative)

public:
	FirebaseFirestoreNative();
	~FirebaseFirestoreNative() override;
	// Registry calls this before deleting the shared Firebase App.
	static void shutdown_all();

	// A non-empty `p_emulator_host` ("host:port") uses the Firestore emulator.
	godot::Error initialize(const godot::String &p_emulator_host = "");
	int64_t get_doc(const godot::String &p_path, const godot::String &p_source = "default");
	int64_t set_doc(const godot::String &p_path, const godot::Dictionary &p_data, bool p_merge);
	int64_t update_doc(const godot::String &p_path, const godot::Dictionary &p_data);
	int64_t delete_doc(const godot::String &p_path);
	// Cursor: {start_at | start_after, end_at | end_before}, each an Array of order_by values.
	int64_t run_query(const godot::String &p_collection, const godot::Array &p_filters, const godot::Array &p_order_by, int64_t p_limit, const godot::String &p_source = "default", const godot::Dictionary &p_cursor = godot::Dictionary());
	int64_t run_query_snapshot(const godot::String &p_collection, const godot::Array &p_filters, const godot::Array &p_order_by, int64_t p_limit, const godot::String &p_source = "default", const godot::Dictionary &p_cursor = godot::Dictionary());
	// Server-side count of the matching documents.
	int64_t run_count(const godot::String &p_collection, const godot::Array &p_filters);
	int64_t set_network_enabled(bool p_enabled);
	int64_t wait_pending_writes();
	// Ops: {op = "set", path, data, merge} | {op = "update", path, data} | {op = "delete", path}.
	int64_t commit_batch(const godot::Array &p_ops);
	// Emits document_changed(listener_id, ok, snapshot, error_code, error_message).
	int64_t listen_doc(const godot::String &p_path, bool p_include_metadata_changes = false);
	// Emits query_changed(listener_id, ok, {documents, metadata}, error_code, error_message); 0 for an invalid query.
	int64_t listen_query(const godot::String &p_collection, const godot::Array &p_filters, const godot::Array &p_order_by, int64_t p_limit, const godot::Dictionary &p_cursor = godot::Dictionary(), bool p_include_metadata_changes = false);
	void remove_listener(int64_t p_id);

protected:
	static void _bind_methods();

private:
	void remove_all_listeners();

	// Runs `p_request` with the document at `p_path`, or fails for an invalid path.
	int64_t start_with_document(const godot::String &p_path, const std::function<void(firebase::firestore::DocumentReference, Completion)> &p_request);

	int64_t start_query(const godot::String &p_collection, const godot::Array &p_filters, const godot::Array &p_order_by, int64_t p_limit, const godot::String &p_source, const godot::Dictionary &p_cursor, bool p_with_metadata);

	firebase::firestore::Firestore *db = nullptr;
	std::unordered_map<int64_t, firebase::firestore::ListenerRegistration> listeners;
	int64_t next_listener_id = 0;
};

} // namespace godot_firebase
