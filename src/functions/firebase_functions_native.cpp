#include "firebase_functions_native.h"

#include <unordered_set>
#include <utility>

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../core/firebase_app_native.h"
#include "../core/variant_convert.h"

using firebase::Future;
using firebase::functions::HttpsCallableResult;
using godot::D_METHOD;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

// FirebaseFunctions.REGION_SETTING and DEFAULT_REGION.
const char *const kRegionSetting = "firebase/functions/region";
const char *const kDefaultRegion = "us-central1";

std::unordered_set<FirebaseFunctionsNative *> active_modules;

} // namespace

FirebaseFunctionsNative::FirebaseFunctionsNative() {
	active_modules.insert(this);
}

FirebaseFunctionsNative::~FirebaseFunctionsNative() {
	active_modules.erase(this);
}

void FirebaseFunctionsNative::shutdown_all() {
	// The Functions instance belongs to the App; later calls fail as unavailable.
	for (FirebaseFunctionsNative *module : active_modules) {
		module->functions = nullptr;
	}
}

godot::Error FirebaseFunctionsNative::initialize() {
	if (functions) {
		return godot::ERR_ALREADY_IN_USE;
	}
	firebase::App *app = FirebaseAppNative::get_app();
	if (app == nullptr) {
		return godot::ERR_UNCONFIGURED;
	}
	const String region = godot::ProjectSettings::get_singleton()->get_setting(kRegionSetting, kDefaultRegion);
	firebase::InitResult result = firebase::kInitResultSuccess;
	functions = firebase::functions::Functions::GetInstance(app, to_std(region).c_str(), &result);
	if (functions == nullptr || result != firebase::kInitResultSuccess) {
		functions = nullptr;
		return godot::ERR_CANT_CREATE;
	}
	return godot::OK;
}

int64_t FirebaseFunctionsNative::call_function(const String &p_name, const Variant &p_data) {
	return start([this, &p_name, &p_data](Completion done) {
		if (functions == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseFunctionsNative is not initialized"));
			return;
		}
		const std::string name = to_std(p_name);
		if (name.empty() || name.find('\0') != std::string::npos) {
			done(Outcome::failure(kInvalidArgument, "function name must be non-empty and contain no NUL"));
			return;
		}
		firebase::Variant data;
		const String reason = to_firebase_variant(p_data, data);
		if (!reason.is_empty()) {
			done(Outcome::failure(kInvalidArgument, reason));
			return;
		}
		complete_when_done(functions->GetHttpsCallable(name.c_str()).Call(data), std::move(done), [](const Future<HttpsCallableResult> &future) {
			return to_godot_variant(future.result()->data());
		});
	});
}

void FirebaseFunctionsNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseFunctionsNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("call_function", "name", "data"), &FirebaseFunctionsNative::call_function);
}

} // namespace godot_firebase
