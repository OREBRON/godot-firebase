#pragma once
#include <godot_cpp/variant/dictionary.hpp>
#include "../../core/outcome.h"

namespace godot_firebase {
// Uses the existing default App; never configures another App or collection default.
godot::Error initialize_crashlytics_platform();
void dispatch_crashlytics(const godot::String &p_operation, const godot::Dictionary &p_payload, int64_t p_id);
// Thread-safe, consumes a token once. Late callbacks after shutdown are ignored.
void finish_crashlytics_request(int64_t p_id, Outcome p_result);
} // namespace godot_firebase
