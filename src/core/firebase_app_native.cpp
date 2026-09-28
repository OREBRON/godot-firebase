#include "firebase_app_native.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot_firebase {

namespace {
firebase::App *app = nullptr;
}

godot::Error FirebaseAppNative::initialize() {
	if (app) {
		return godot::ERR_ALREADY_IN_USE;
	}
	app = firebase::App::Create();
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
	godot::ClassDB::bind_static_method("FirebaseAppNative", godot::D_METHOD("initialize"), &FirebaseAppNative::initialize);
}

} // namespace godot_firebase
