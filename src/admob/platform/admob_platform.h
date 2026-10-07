#pragma once
#include <godot_cpp/variant/dictionary.hpp>
#include "../../core/outcome.h"

namespace godot_firebase {
// Google Mobile Ads and UMP bridges (admob_android.cpp, admob_ios.mm).
godot::Error initialize_admob_platform();
// Runs `p_operation` with `p_payload`; the bridge answers through
// finish_admob_request(p_token, ...). Token 0 expects no answer.
void dispatch_admob(const godot::String &p_operation, const godot::Dictionary &p_payload, int64_t p_token);
// Releases every platform ad; later bridge callbacks are ignored.
void shutdown_admob_platform();

// Called by the bridges from any thread. Each token completes once; an ad's
// events must precede the completion of its show request.
void finish_admob_request(int64_t p_token, Outcome p_result);
void emit_admob_event(int64_t p_ad_id, const godot::String &p_event);
} // namespace godot_firebase
