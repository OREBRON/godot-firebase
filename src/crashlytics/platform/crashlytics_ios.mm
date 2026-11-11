#include "crashlytics_platform.h"
#import <FirebaseCrashlytics/FirebaseCrashlytics.h>

namespace {
NSString *text(const godot::String &value) {
	const godot::CharString utf8 = value.utf8();
	return [[NSString alloc] initWithBytes:utf8.get_data() length:utf8.length() encoding:NSUTF8StringEncoding];
}
id scalar(const godot::Variant &value) {
	switch (value.get_type()) {
		case godot::Variant::STRING: return text(value);
		case godot::Variant::BOOL: return @(static_cast<bool>(value));
		case godot::Variant::INT: return @(static_cast<int64_t>(value));
		case godot::Variant::FLOAT: return @(static_cast<double>(value));
		default: return nil;
	}
}
} // namespace
namespace godot_firebase {
godot::Error initialize_crashlytics_platform() {
	@try { return [FIRCrashlytics crashlytics] ? godot::OK : godot::ERR_UNAVAILABLE; }
	@catch (NSException *) { return godot::ERR_UNAVAILABLE; }
}
void dispatch_crashlytics(const godot::String &operation, const godot::Dictionary &data, int64_t id) {
	@try {
		FIRCrashlytics *crashlytics = [FIRCrashlytics crashlytics];
		if (operation == "log_message") [crashlytics log:text(data["message"])];
		else if (operation == "set_custom_key") [crashlytics setCustomValue:scalar(data["value"]) forKey:text(data["key"])];
		else if (operation == "set_custom_keys") {
			const godot::Dictionary keys = data["keys"];
			const godot::Array names = keys.keys();
			NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:names.size()];
			for (int64_t i = 0; i < names.size(); i++) values[text(names[i])] = scalar(keys[names[i]]);
			[crashlytics setCustomKeysAndValues:values];
		}
		else if (operation == "set_user_id") [crashlytics setUserID:text(data["user_id"])];
		else if (operation == "record_error") {
			FIRExceptionModel *model = [[FIRExceptionModel alloc] initWithName:text(data["name"]) reason:text(data["message"])];
			const godot::Array frames = data["stack"];
			NSMutableArray<FIRStackFrame *> *stack = [NSMutableArray arrayWithCapacity:frames.size()];
			for (int64_t i = 0; i < frames.size(); i++) {
				const godot::Dictionary frame = frames[i];
				[stack addObject:[[FIRStackFrame alloc] initWithSymbol:text(frame["function"]) file:text(frame["file"]) line:static_cast<int64_t>(frame["line"])]];
			}
			model.stackTrace = stack;
			[crashlytics recordExceptionModel:model];
		} else if (operation == "set_collection_enabled") [crashlytics setCrashlyticsCollectionEnabled:static_cast<bool>(data["enabled"])];
		else if (operation == "is_collection_enabled") {
			finish_crashlytics_request(id, Outcome::success(static_cast<bool>(crashlytics.isCrashlyticsCollectionEnabled)));
			return;
		} else if (operation == "did_crash_previous_execution") {
			finish_crashlytics_request(id, Outcome::success(static_cast<bool>(crashlytics.didCrashDuringPreviousExecution)));
			return;
		} else if (operation == "check_unsent_reports") {
			// On iOS the SDK does not invoke the completion when collection is enabled.
			if (crashlytics.isCrashlyticsCollectionEnabled) finish_crashlytics_request(id, Outcome::success(false));
			else [crashlytics checkForUnsentReportsWithCompletion:^(BOOL available) {
				finish_crashlytics_request(id, Outcome::success(static_cast<bool>(available)));
			}];
			return;
		} else if (operation == "send_unsent_reports") [crashlytics sendUnsentReports];
		else if (operation == "delete_unsent_reports") [crashlytics deleteUnsentReports];
		else {
			finish_crashlytics_request(id, Outcome::failure(kInvalidArgument, "Unknown Crashlytics operation"));
			return;
		}
		finish_crashlytics_request(id, Outcome::success());
	} @catch (NSException *) {
		finish_crashlytics_request(id, Outcome::failure(kUnavailable, "iOS Crashlytics local call failed"));
	}
}
} // namespace godot_firebase
