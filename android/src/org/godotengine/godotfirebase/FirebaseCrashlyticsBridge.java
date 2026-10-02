package org.godotengine.godotfirebase;

import com.google.firebase.crashlytics.FirebaseCrashlytics;
import org.json.JSONArray;
import org.json.JSONObject;

/** Crashlytics annotations on the already configured default FirebaseApp. */
public final class FirebaseCrashlyticsBridge {
    private FirebaseCrashlyticsBridge() {}

    public static boolean initialize() {
        try {
            return FirebaseCrashlytics.getInstance() != null;
        } catch (RuntimeException error) {
            return false;
        }
    }

    public static void request(String operation, String json, long requestId) {
        try {
            FirebaseCrashlytics crashlytics = FirebaseCrashlytics.getInstance();
            JSONObject data = new JSONObject(json);
            switch (operation) {
                case "log_message":
                    crashlytics.log(data.getString("message"));
                    break;
                case "set_custom_key":
                    String key = data.getString("key");
                    Object value = data.get("value");
                    if (value instanceof String) crashlytics.setCustomKey(key, (String) value);
                    else if (value instanceof Boolean) crashlytics.setCustomKey(key, (Boolean) value);
                    else if (value instanceof Integer || value instanceof Long) crashlytics.setCustomKey(key, ((Number) value).longValue());
                    else if (value instanceof Number && Double.isFinite(((Number) value).doubleValue())) crashlytics.setCustomKey(key, ((Number) value).doubleValue());
                    else throw new IllegalArgumentException("Invalid custom key value");
                    break;
                case "set_user_id":
                    crashlytics.setUserId(data.getString("user_id"));
                    break;
                case "record_error":
                    JSONArray frames = data.getJSONArray("stack");
                    StackTraceElement[] stack = new StackTraceElement[frames.length()];
                    for (int i = 0; i < frames.length(); i++) {
                        JSONObject frame = frames.getJSONObject(i);
                        stack[i] = new StackTraceElement("GDScript", frame.getString("function"), frame.getString("file"), frame.getInt("line"));
                    }
                    GodotNonfatalError error = new GodotNonfatalError(data.getString("name"), data.getString("message"));
                    // An empty supplied trace remains empty; do not invent Java bridge frames.
                    error.setStackTrace(stack);
                    crashlytics.recordException(error);
                    break;
                case "set_collection_enabled":
                    crashlytics.setCrashlyticsCollectionEnabled(data.getBoolean("enabled"));
                    break;
                case "is_collection_enabled":
                    succeed(requestId, crashlytics.isCrashlyticsCollectionEnabled());
                    return;
                case "did_crash_previous_execution":
                    succeed(requestId, crashlytics.didCrashOnPreviousExecution());
                    return;
                case "check_unsent_reports":
                    if (crashlytics.isCrashlyticsCollectionEnabled()) {
                        succeed(requestId, false);
                    } else {
                        crashlytics.checkForUnsentReports().addOnCompleteListener(task -> {
                            if (task.isSuccessful()) succeed(requestId, Boolean.TRUE.equals(task.getResult()));
                            else fail(requestId, "Crashlytics report check failed");
                        });
                    }
                    return;
                case "send_unsent_reports":
                    crashlytics.sendUnsentReports();
                    break;
                case "delete_unsent_reports":
                    crashlytics.deleteUnsentReports();
                    break;
                default:
                    throw new IllegalArgumentException("Unknown Crashlytics operation");
            }
            nativeComplete(requestId, 0, "", false, false);
        } catch (Exception error) {
            fail(requestId, "Crashlytics local call failed: " + error.getClass().getSimpleName());
        }
    }

    private static void succeed(long id, boolean value) { nativeComplete(id, 0, "", true, value); }
    private static void fail(long id, String message) { nativeComplete(id, -3, message, false, false); }
    private static native void nativeComplete(long id, int code, String message, boolean hasValue, boolean value);

    // Android's report type is this class; the caller's GDScript name is retained in its message.
    private static final class GodotNonfatalError extends RuntimeException {
        GodotNonfatalError(String name, String message) { super(name + ": " + message); }
    }
}
