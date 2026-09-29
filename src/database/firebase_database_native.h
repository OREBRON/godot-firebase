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

	godot::Error initialize();
	int64_t get_value(const godot::String &p_path);
	int64_t set_value(const godot::String &p_path, const godot::Variant &p_value);
	// Keys of `p_values` may be child paths like "stats/level".
	int64_t update_children(const godot::String &p_path, const godot::Dictionary &p_values);
	int64_t remove_value(const godot::String &p_path);
	// Result value is the new key.
	int64_t push_value(const godot::String &p_path, const godot::Variant &p_value);
	// Emits value_changed(listener_id, ok, snapshot, error_code, error_message).
	int64_t listen_value(const godot::String &p_path);
	void remove_listener(int64_t p_id);

protected:
	static void _bind_methods();

private:
	class Listener;

	// Runs `p_request` with the reference at `p_path`, or fails for an invalid path.
	int64_t start_with_reference(const godot::String &p_path, const std::function<void(firebase::database::DatabaseReference, Completion)> &p_request);
	firebase::database::DatabaseReference reference(const godot::String &p_path) const;

	firebase::database::Database *db = nullptr;
	std::unordered_map<int64_t, std::unique_ptr<Listener>> listeners;
	int64_t next_listener_id = 0;
};

} // namespace godot_firebase
