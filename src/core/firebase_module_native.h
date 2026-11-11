#pragma once

#include <cstdint>
#include <functional>
#include <string>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include "outcome.h"

namespace godot_firebase {

// Base of the module classes. Firebase answers on its own threads; this class
// moves every answer to the main thread and drops it when the module is gone.
class FirebaseModuleNative : public godot::RefCounted {
	GDCLASS(FirebaseModuleNative, godot::RefCounted)

protected:
	static void _bind_methods();

	// Allocates a request id and runs `p_request` with its completion.
	// The completion emits request_completed(id, ok, value, error_code, error_message).
	int64_t start(const std::function<void(Completion)> &p_request);
	// Emits `p_signal` with `p_args` on the main thread. Callable from any thread.
	void emit_deferred(const godot::StringName &p_signal, const godot::Array &p_args) const;
	// Same, for callbacks that may outlive the module: skipped once it is freed.
	static void emit_deferred_to(uint64_t p_object_id, const godot::StringName &p_signal, const godot::Array &p_args);
	// Listener generation is checked on delivery, so stop/restart cancels already queued events.
	static void emit_deferred_checked_to(uint64_t p_object_id, const godot::StringName &p_signal, const godot::Array &p_args, int64_t p_generation);
	virtual bool accepts_deferred_event(const godot::StringName &p_signal, int64_t p_generation) const;
	// Splits the "host:port" of project setting firebase/<module>/emulator_host with the
	// rule of Firebase._is_valid_emulator_host(); "" gives an empty host. False when invalid.
	static bool parse_emulator_host(const godot::String &p_value, std::string &r_host, int &r_port);


private:
	static void deliver(uint64_t p_object_id, const godot::StringName &p_signal, const godot::Array &p_args, bool p_checked, int64_t p_generation);

	int64_t next_request_id = 0;
};

} // namespace godot_firebase
