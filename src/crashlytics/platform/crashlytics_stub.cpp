#include "crashlytics_platform.h"
namespace godot_firebase {
godot::Error initialize_crashlytics_platform() { return godot::ERR_UNAVAILABLE; }
void dispatch_crashlytics(const godot::String &, const godot::Dictionary &, int64_t id) {
	finish_crashlytics_request(id, Outcome::failure(kUnsupported, "Crashlytics requires an Android or iOS export"));
}
} // namespace godot_firebase
