#pragma once

#include <memory>
#include <unordered_map>

#include <firebase/database.h>
#include <godot_cpp/variant/dictionary.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Realtime Database. Method names and signals match
// addons/firebase/database/firebase_database_mock.gd.
// Paths are slash-separated keys, "" is the root. Snapshots are {key, exists, value}.
class FirebaseDatabaseNative : public FirebaseModuleNative {
	GDCLASS(FirebaseDatabaseNative, FirebaseModuleNative)

public:
	// Out of line: Listener is complete only in the .cpp file.
	FirebaseDatabaseNative();
	~FirebaseDatabaseNative() override;
	// Registry calls this before deleting the shared Firebase App.
	static void shutdown_all();

	godot::Error initialize(bool p_persistence_enabled = false);
	int64_t set_network_enabled(bool p_enabled);
	// A non-empty `p_query` delivers the matching children in query order.
	int64_t get_value(const godot::String &p_path, const godot::Dictionary &p_query);
	int64_t set_value(const godot::String &p_path, const godot::Variant &p_value);
	// Keys of `p_values` may be child paths like "stats/level".
	int64_t update_children(const godot::String &p_path, const godot::Dictionary &p_values);
	int64_t remove_value(const godot::String &p_path);
	// Result value is the new key.
	int64_t push_value(const godot::String &p_path, const godot::Variant &p_value);
	// Completion acknowledges server registration/cancellation, not action execution.
	int64_t on_disconnect_set_value(const godot::String &p_path, const godot::Variant &p_value);
	int64_t on_disconnect_update_children(const godot::String &p_path, const godot::Dictionary &p_values);
	int64_t on_disconnect_remove_value(const godot::String &p_path);
	int64_t on_disconnect_cancel(const godot::String &p_path);
	// Emits value_changed(listener_id, ok, snapshot, error_code, error_message).
	int64_t listen_value(const godot::String &p_path, const godot::Dictionary &p_query);
	void remove_listener(int64_t p_id);

protected:
	static void _bind_methods();

private:
	class Listener;

	// Runs `p_request` with the reference at `p_path`, or fails for an invalid path.
	int64_t start_with_reference(const godot::String &p_path, const std::function<void(firebase::database::DatabaseReference, Completion)> &p_request, bool p_allow_info = false);
	firebase::database::DatabaseReference reference(const godot::String &p_path) const;

	firebase::database::Database *db = nullptr;
	std::unordered_map<int64_t, std::unique_ptr<Listener>> listeners;
	int64_t next_listener_id = 0;
};

} // namespace godot_firebase
