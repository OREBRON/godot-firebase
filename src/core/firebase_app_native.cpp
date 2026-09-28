#include "firebase_app_native.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#include <godot_cpp/core/class_db.hpp>

namespace godot_firebase {

namespace {
firebase::App *app = nullptr;
}

godot::Error FirebaseAppNative::initialize(const godot::String &p_config_json) {
	if (app) {
		return godot::ERR_ALREADY_IN_USE;
	}
#if defined(__APPLE__) && TARGET_OS_IOS
	(void)p_config_json;
	app = firebase::App::Create();
#else
	if (p_config_json.is_empty()) {
		return godot::ERR_UNCONFIGURED;
	}
	firebase::AppOptions options;
	if (!firebase::AppOptions::LoadFromJsonConfig(p_config_json.utf8().get_data(), &options)) {
		return godot::ERR_PARSE_ERROR;
	}
	app = firebase::App::Create(options);
#endif
	return app ? godot::OK : godot::ERR_CANT_CREATE;
}

firebase::App *FirebaseAppNative::get_app() {
	return app;
}

void FirebaseAppNative::shutdown() {
	delete app;
	app = nullptr;
}

void FirebaseAppNative::_bind_methods() {
	godot::ClassDB::bind_static_method("FirebaseAppNative", godot::D_METHOD("initialize", "config_json"), &FirebaseAppNative::initialize);
}

} // namespace godot_firebase
