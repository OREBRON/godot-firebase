package org.godotengine.godotfirebase;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.CancellationSignal;
import androidx.credentials.ClearCredentialStateRequest;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.ClearCredentialException;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.games.PlayGames;
import com.google.android.gms.games.PlayGamesSdk;
import java.util.HashMap;
import java.util.Map;

/** Obtains provider credentials only. Firebase C++ owns the authenticated session. */
public final class FirebaseAuthBridge {
    private static final int INVALID_ARGUMENT = -1, UNSUPPORTED = -2, UNAVAILABLE = -3, CANCELLED = -5;
    // Accessed only on Android's UI thread. IDs carry no token or account data.
    private static final Map<Long, CancellationSignal> pending = new HashMap<>();
    private FirebaseAuthBridge() {}

    public static void request(Activity activity, String provider, String webClientId, long requestId) {
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) {
                nativeComplete(requestId, provider, "", UNAVAILABLE, "sign-in Activity is unavailable");
                return;
            }
            if (!provider.equals("google") && !provider.equals("play_games_platform")) {
                nativeComplete(requestId, provider, "", UNSUPPORTED, "provider is not supported on Android");
                return;
            }
            if (webClientId.isEmpty()) {
                nativeComplete(requestId, provider, "", INVALID_ARGUMENT, "firebase/auth/google_web_client_id is required");
                return;
            }
            CancellationSignal cancellation = new CancellationSignal();
            pending.put(requestId, cancellation);
            try {
                if (provider.equals("google")) google(activity, webClientId, requestId, cancellation);
                else playGames(activity, webClientId, requestId);
            } catch (Exception error) {
                fail(requestId, provider, error);
            } catch (NoClassDefFoundError missingOptionalProvider) {
                complete(requestId, provider, "", UNSUPPORTED, "provider dependencies are not enabled in this export");
            }
        });
    }

    private static void google(Activity activity, String webClientId, long id, CancellationSignal cancellation) {
        GetCredentialRequest request = new GetCredentialRequest.Builder()
                .addCredentialOption(new GetSignInWithGoogleOption.Builder(webClientId).build()).build();
        CredentialManager.create(activity).getCredentialAsync(activity, request, cancellation,
                activity::runOnUiThread, new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                    @Override public void onResult(GetCredentialResponse result) {
                        try {
                            Credential credential = result.getCredential();
                            if (!(credential instanceof CustomCredential)
                                    || !GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) {
                                complete(id, "google", "", UNSUPPORTED, "unexpected Google credential type");
                                return;
                            }
                            String token = GoogleIdTokenCredential.createFrom(credential.getData()).getIdToken();
                            complete(id, "google", token, 0, "");
                        } catch (Exception error) { fail(id, "google", error); }
                    }
                    @Override public void onError(GetCredentialException error) { fail(id, "google", error); }
                });
    }

    private static void playGames(Activity activity, String webClientId, long id) throws PackageManager.NameNotFoundException {
        Bundle metadata = activity.getPackageManager().getApplicationInfo(activity.getPackageName(), PackageManager.GET_META_DATA).metaData;
        if (metadata == null || !metadata.containsKey("com.google.android.gms.games.APP_ID")) {
            complete(id, "play_games_platform", "", INVALID_ARGUMENT, "Play Games application ID is missing from the export");
            return;
        }
        GamesProvider.request(activity, webClientId, id);
    }

    // Keep references to optional PGS types out of the Google provider's class
    // verification. This class is loaded only after export metadata opts in.
    private static final class GamesProvider {
        static void request(Activity activity, String webClientId, long id) {
            PlayGamesSdk.initialize(activity);
            PlayGames.getGamesSignInClient(activity).isAuthenticated().addOnCompleteListener(activity, check -> {
                if (!pending.containsKey(id)) return;
                if (check.isSuccessful() && check.getResult().isAuthenticated()) {
                    code(activity, webClientId, id);
                } else {
                    PlayGames.getGamesSignInClient(activity).signIn().addOnCompleteListener(activity, signIn -> {
                        if (!pending.containsKey(id)) return;
                        if (signIn.isSuccessful() && signIn.getResult().isAuthenticated()) code(activity, webClientId, id);
                        else if (signIn.getException() != null) fail(id, "play_games_platform", signIn.getException());
                        else complete(id, "play_games_platform", "", CANCELLED, "Play Games sign-in was cancelled");
                    });
                }
            });
        }

        private static void code(Activity activity, String webClientId, long id) {
            PlayGames.getGamesSignInClient(activity).requestServerSideAccess(webClientId, false)
                    .addOnCompleteListener(activity, result -> {
                        if (result.isSuccessful()) complete(id, "play_games_platform", result.getResult(), 0, "");
                        else fail(id, "play_games_platform", result.getException());
                    });
        }
    }

    private static void fail(long id, String provider, Exception error) {
        int code = UNAVAILABLE;
        if (error instanceof GetCredentialCancellationException) code = CANCELLED;
        else if (error instanceof ApiException && ((ApiException) error).getStatusCode() == CommonStatusCodes.CANCELED) code = CANCELLED;
        // Do not expose SDK exception messages that may include OAuth response data.
        complete(id, provider, "", code, code == CANCELLED ? "provider sign-in was cancelled" : "provider sign-in failed");
    }

    private static void complete(long id, String provider, String credential, int code, String message) {
        if (pending.remove(id) == null) return;
        if (code == 0 && (credential == null || credential.isEmpty())) {
            code = UNAVAILABLE;
            message = "provider did not return a credential";
        }
        nativeComplete(id, provider, credential == null ? "" : credential, code, message);
    }

    public static void clearState(Activity activity) {
        activity.runOnUiThread(() -> {
            CancellationSignal[] signals = pending.values().toArray(new CancellationSignal[0]);
            pending.clear();
            for (CancellationSignal signal : signals) signal.cancel();
            CredentialManager.create(activity).clearCredentialStateAsync(new ClearCredentialStateRequest(), null,
                    activity::runOnUiThread, new CredentialManagerCallback<Void, ClearCredentialException>() {
                        @Override public void onResult(Void ignored) {}
                        @Override public void onError(ClearCredentialException ignored) {}
                    });
        });
    }

    private static native void nativeComplete(long requestId, String provider, String credential, int errorCode, String message);
}
