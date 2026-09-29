package org.godotengine.godotfirebase;

import android.app.Activity;

public final class FirebaseBridge {
    private FirebaseBridge() {}

    public static int initialize(Activity activity) {
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
        return nativeInitialize(activity);
    }

    private static native int nativeInitialize(Activity activity);
}