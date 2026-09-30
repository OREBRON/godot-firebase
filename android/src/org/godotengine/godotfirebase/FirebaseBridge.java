package org.godotengine.godotfirebase;

import android.app.Activity;

public final class FirebaseBridge {
    private FirebaseBridge() {}

    // The options of this package, picked by FirebaseAndroidConfig from the
    // game's google-services.json.
    public static int initialize(Activity activity, String appId, String apiKey, String projectId,
            String storageBucket, String databaseUrl, String messagingSenderId) {
        if (activity == null) {
            return 31;
        }
        try {
            System.loadLibrary("godot_firebase.android.template_release");
        } catch (UnsatisfiedLinkError releaseError) {
            try {
                System.loadLibrary("godot_firebase.android.template_debug");
            } catch (UnsatisfiedLinkError debugError) {
                return 2;
            }
        }
        return nativeInitialize(activity, appId, apiKey, projectId, storageBucket, databaseUrl, messagingSenderId);
    }

    private static native int nativeInitialize(Activity activity, String appId, String apiKey, String projectId,
            String storageBucket, String databaseUrl, String messagingSenderId);
}
