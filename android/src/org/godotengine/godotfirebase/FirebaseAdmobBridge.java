package org.godotengine.godotfirebase;

import android.app.Activity;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import com.google.android.libraries.ads.mobile.sdk.MobileAds;
import com.google.android.libraries.ads.mobile.sdk.common.AdLoadCallback;
import com.google.android.libraries.ads.mobile.sdk.common.AdRequest;
import com.google.android.libraries.ads.mobile.sdk.common.AgeRestrictedTreatment;
import com.google.android.libraries.ads.mobile.sdk.common.FullScreenContentError;
import com.google.android.libraries.ads.mobile.sdk.common.LoadAdError;
import com.google.android.libraries.ads.mobile.sdk.common.RequestConfiguration;
import com.google.android.libraries.ads.mobile.sdk.initialization.InitializationConfig;
import com.google.android.libraries.ads.mobile.sdk.rewarded.RewardItem;
import com.google.android.libraries.ads.mobile.sdk.rewarded.RewardedAd;
import com.google.android.libraries.ads.mobile.sdk.rewarded.RewardedAdEventCallback;
import com.google.android.libraries.ads.mobile.sdk.rewarded.ServerSideVerificationOptions;
import com.google.android.ump.ConsentDebugSettings;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.FormError;
import com.google.android.ump.UserMessagingPlatform;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Rewarded ads (Google Mobile Ads Next-Gen SDK) and UMP consent for FirebaseAdmobNative. */
public final class FirebaseAdmobBridge {
    // FirebaseResult.ERR_* and FirebaseAdmob.ERROR_* codes.
    private static final int ERR_INVALID_ARGUMENT = -1;
    private static final int ERROR_INTERNAL = 1;
    private static final int ERROR_INVALID_REQUEST = 2;
    private static final int ERROR_NETWORK = 3;
    private static final int ERROR_NO_FILL = 4;
    private static final int ERROR_APP_ID_MISSING = 5;
    private static final int ERROR_AD_ALREADY_USED = 7;
    private static final int ERROR_SHOW_FAILED = 8;
    // The export writes the App ID here; UMP reads it and Next-Gen takes it in code.
    private static final String APP_ID_KEY = "com.google.android.gms.ads.APPLICATION_ID";

    private static final Handler main = new Handler(Looper.getMainLooper());
    // MobileAds.initialize() may block; initialization and loads run in order here.
    private static final ExecutorService worker = Executors.newSingleThreadExecutor();
    private static final Map<Long, RewardedAd> ads = new HashMap<>();
    private static volatile RequestConfiguration requestConfiguration = new RequestConfiguration.Builder().build();
    // Shutdown increments it; answers of earlier requests are dropped.
    private static volatile int generation;
    private static boolean initialized; // worker thread only

    private FirebaseAdmobBridge() {}

    public static boolean initialize(Activity activity) {
        return activity != null;
    }

    /** Called from Godot's thread. Token 0 expects no answer. */
    public static void request(Activity activity, String operation, String json, long token) {
        int current = generation;
        try {
            JSONObject data = new JSONObject(json);
            switch (operation) {
                case "request_consent":
                    requestConsent(activity, data, token, current);
                    break;
                case "show_privacy_options":
                    showPrivacyOptions(activity, token, current);
                    break;
                case "reset_consent":
                    main.post(() -> {
                        UserMessagingPlatform.getConsentInformation(activity).reset();
                        complete(token, current);
                    });
                    break;
                case "set_request_configuration":
                    setRequestConfiguration(data, token, current);
                    break;
                case "load_rewarded":
                    load(activity.getApplicationContext(), data.getLong("ad_id"), data.getString("ad_unit_id"), token, current);
                    break;
                case "show_rewarded":
                    show(activity, data, token, current);
                    break;
                case "release_rewarded":
                    release(data.getLong("ad_id"));
                    break;
                default:
                    fail(token, current, ERR_INVALID_ARGUMENT, "Unknown AdMob operation");
            }
        } catch (Exception error) {
            fail(token, current, ERROR_INTERNAL, "AdMob bridge failed: " + error.getClass().getSimpleName());
        }
    }

    /** Releases every ad; answers of earlier requests are dropped. */
    public static void shutdown() {
        generation++;
        List<RewardedAd> released;
        synchronized (ads) {
            released = new ArrayList<>(ads.values());
            ads.clear();
        }
        main.post(() -> {
            for (RewardedAd ad : released) ad.destroy();
        });
    }

    // UMP: update the consent information every launch, then show the form if required.
    private static void requestConsent(Activity activity, JSONObject options, long token, int current) throws JSONException {
        ConsentRequestParameters.Builder parameters = new ConsentRequestParameters.Builder();
        if (options.length() > 0) parameters.setConsentDebugSettings(debugSettings(activity, options));
        ConsentRequestParameters request = parameters.build();
        main.post(() -> {
            ConsentInformation consent = UserMessagingPlatform.getConsentInformation(activity);
            consent.requestConsentInfoUpdate(activity, request,
                    () -> UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity, error -> answerConsent(token, current, consent, error)),
                    error -> answerConsent(token, current, consent, error));
        });
    }

    private static ConsentDebugSettings debugSettings(Context context, JSONObject options) throws JSONException {
        ConsentDebugSettings.Builder debug = new ConsentDebugSettings.Builder(context);
        switch (options.optString("debug_geography")) {
            case "eea":
                debug.setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA);
                break;
            case "other":
                debug.setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_OTHER);
                break;
            case "regulated_us_state":
                debug.setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_REGULATED_US_STATE);
                break;
            default:
                break;
        }
        JSONArray ids = options.optJSONArray("test_device_hashed_ids");
        for (int i = 0; ids != null && i < ids.length(); i++) debug.addTestDeviceHashedId(ids.getString(i));
        return debug.build();
    }

    private static void showPrivacyOptions(Activity activity, long token, int current) {
        main.post(() -> {
            ConsentInformation consent = UserMessagingPlatform.getConsentInformation(activity);
            if (consent.getPrivacyOptionsRequirementStatus() != ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED) {
                answerConsent(token, current, consent, null);
                return;
            }
            UserMessagingPlatform.showPrivacyOptionsForm(activity, error -> answerConsent(token, current, consent, error));
        });
    }

    private static void answerConsent(long token, int current, ConsentInformation consent, FormError error) {
        if (error != null) {
            boolean network = error.getErrorCode() == FormError.ErrorCode.INTERNET_ERROR || error.getErrorCode() == FormError.ErrorCode.TIME_OUT;
            fail(token, current, network ? ERROR_NETWORK : ERROR_INTERNAL, "Consent failed: " + error.getMessage());
            return;
        }
        if (current != generation) return;
        boolean privacyOptions = consent.getPrivacyOptionsRequirementStatus() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
        nativeConsent(token, consent.canRequestAds(), consentStatus(consent.getConsentStatus()), privacyOptions);
    }

    private static String consentStatus(int status) {
        switch (status) {
            case ConsentInformation.ConsentStatus.REQUIRED:
                return "required";
            case ConsentInformation.ConsentStatus.NOT_REQUIRED:
                return "not_required";
            case ConsentInformation.ConsentStatus.OBTAINED:
                return "obtained";
            default:
                return "unknown";
        }
    }

    // A new configuration replaces the previous one; absent keys use SDK defaults.
    private static void setRequestConfiguration(JSONObject config, long token, int current) throws JSONException {
        RequestConfiguration.Builder builder = new RequestConfiguration.Builder();
        JSONArray ids = config.optJSONArray("test_device_ids");
        if (ids != null) {
            List<String> devices = new ArrayList<>();
            for (int i = 0; i < ids.length(); i++) devices.add(ids.getString(i));
            builder.setTestDeviceIds(devices);
        }
        if (config.has("max_ad_content_rating")) builder.setMaxAdContentRating(contentRating(config.getString("max_ad_content_rating")));
        if (config.has("age_restricted_treatment")) {
            builder.setAgeRestrictedTreatment("child".equals(config.getString("age_restricted_treatment"))
                    ? AgeRestrictedTreatment.CHILD
                    : AgeRestrictedTreatment.TEEN);
        }
        RequestConfiguration built = builder.build();
        worker.execute(() -> {
            requestConfiguration = built;
            if (initialized) MobileAds.setRequestConfiguration(built);
            complete(token, current);
        });
    }

    private static RequestConfiguration.MaxAdContentRating contentRating(String rating) {
        switch (rating) {
            case "G":
                return RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_G;
            case "PG":
                return RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_PG;
            case "T":
                return RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_T;
            case "MA":
                return RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_MA;
            default:
                return RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_UNSPECIFIED;
        }
    }

    private static void load(Context context, long adId, String adUnitId, long token, int current) {
        worker.execute(() -> {
            String missing = ensureInitialized(context);
            if (missing != null) {
                fail(token, current, ERROR_APP_ID_MISSING, missing);
                return;
            }
            RewardedAd.load(new AdRequest.Builder(adUnitId).build(), new AdLoadCallback<RewardedAd>() {
                @Override
                public void onAdLoaded(RewardedAd ad) {
                    if (current != generation) {
                        main.post(ad::destroy);
                        return;
                    }
                    synchronized (ads) {
                        ads.put(adId, ad);
                    }
                    complete(token, current);
                }

                @Override
                public void onAdFailedToLoad(LoadAdError error) {
                    fail(token, current, loadError(error.getCode()), "Rewarded ad failed to load: " + error.getMessage());
                }
            });
        });
    }

    // Worker thread. Ads requested before initialization completes would wait anyway.
    private static String ensureInitialized(Context context) {
        if (initialized) return null;
        String appId = applicationId(context);
        if (appId == null) return "AdMob App ID is missing from the Android manifest; set firebase/admob_app_id in the export preset";
        CountDownLatch ready = new CountDownLatch(1);
        InitializationConfig config = new InitializationConfig.Builder(appId).setRequestConfiguration(requestConfiguration).build();
        MobileAds.initialize(context, config, status -> ready.countDown());
        try {
            ready.await(30, TimeUnit.SECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
        initialized = true;
        return null;
    }

    @SuppressWarnings("deprecation")
    private static String applicationId(Context context) {
        try {
            ApplicationInfo info = context.getPackageManager().getApplicationInfo(context.getPackageName(), PackageManager.GET_META_DATA);
            Bundle metadata = info.metaData;
            String appId = metadata == null ? null : metadata.getString(APP_ID_KEY);
            return appId == null || appId.isEmpty() ? null : appId;
        } catch (PackageManager.NameNotFoundException error) {
            return null;
        }
    }

    private static int loadError(LoadAdError.ErrorCode code) {
        switch (code) {
            case INVALID_REQUEST:
            case NOT_FOUND:
                return ERROR_INVALID_REQUEST;
            case NETWORK_ERROR:
            case TIMEOUT:
                return ERROR_NETWORK;
            case NO_FILL:
                return ERROR_NO_FILL;
            case APP_ID_MISSING:
                return ERROR_APP_ID_MISSING;
            case AD_RESPONSE_ALREADY_USED:
                return ERROR_AD_ALREADY_USED;
            default:
                return ERROR_INTERNAL;
        }
    }

    // The ad's events precede the answer of its show request, as native expects.
    private static void show(Activity activity, JSONObject data, long token, int current) {
        long adId = data.optLong("ad_id");
        RewardedAd ad;
        synchronized (ads) {
            ad = ads.remove(adId);
        }
        if (ad == null) {
            fail(token, current, ERR_INVALID_ARGUMENT, "Unknown rewarded ad");
            return;
        }
        String userId = data.optString("user_id");
        String customData = data.optString("custom_data");
        if (!userId.isEmpty() || !customData.isEmpty()) ad.setServerSideVerificationOptions(new ServerSideVerificationOptions(userId, customData));
        AtomicReference<RewardItem> earned = new AtomicReference<>();
        ad.setAdEventCallback(new RewardedAdEventCallback() {
            @Override
            public void onAdShowedFullScreenContent() {
                event(adId, current, "opened");
            }

            @Override
            public void onAdImpression() {
                event(adId, current, "impression");
            }

            @Override
            public void onAdClicked() {
                event(adId, current, "clicked");
            }

            @Override
            public void onAdFailedToShowFullScreenContent(FullScreenContentError error) {
                event(adId, current, "failed_to_show");
                boolean reused = error.getCode() == FullScreenContentError.ErrorCode.AD_REUSED;
                fail(token, current, reused ? ERROR_AD_ALREADY_USED : ERROR_SHOW_FAILED, "Rewarded ad failed to show: " + error.getMessage());
                main.post(ad::destroy);
            }

            @Override
            public void onAdDismissedFullScreenContent() {
                event(adId, current, "closed");
                RewardItem reward = earned.get();
                if (current == generation) nativeReward(token, reward != null, reward == null ? "" : reward.getType(), reward == null ? 0 : reward.getAmount());
                main.post(ad::destroy);
            }
        });
        main.post(() -> {
            try {
                ad.show(activity, reward -> {
                    earned.set(reward);
                    event(adId, current, "reward_earned");
                });
            } catch (RuntimeException error) {
                event(adId, current, "failed_to_show");
                fail(token, current, ERROR_SHOW_FAILED, "Rewarded ad failed to show: " + error.getClass().getSimpleName());
                ad.destroy();
            }
        });
    }

    private static void release(long adId) {
        RewardedAd ad;
        synchronized (ads) {
            ad = ads.remove(adId);
        }
        if (ad != null) main.post(ad::destroy);
    }

    private static void event(long adId, int current, String name) {
        if (current == generation) nativeEvent(adId, name);
    }

    private static void complete(long token, int current) {
        if (token != 0 && current == generation) nativeComplete(token, 0, "");
    }

    private static void fail(long token, int current, int code, String message) {
        if (token != 0 && current == generation) nativeComplete(token, code, message);
    }

    private static native void nativeComplete(long token, int code, String message);
    private static native void nativeConsent(long token, boolean canRequestAds, String consentStatus, boolean privacyOptionsRequired);
    private static native void nativeReward(long token, boolean rewarded, String rewardType, int rewardAmount);
    private static native void nativeEvent(long adId, String event);
}
