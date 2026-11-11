#pragma once

#include <firebase/auth.h>
#include <memory>
#include <godot_cpp/variant/dictionary.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Firebase Authentication. Method names match addons/firebase/auth/firebase_auth_mock.gd.
// Users are {uid, email, display_name, photo_url, is_anonymous, providers}; {} means signed out.
struct AuthSession;

// What an operation does with the credential it obtains.
enum class CredentialUse { kSignIn, kLink, kReauthenticate };

class FirebaseAuthNative : public FirebaseModuleNative, private firebase::auth::AuthStateListener {
	GDCLASS(FirebaseAuthNative, FirebaseModuleNative)

public:
	FirebaseAuthNative();
	~FirebaseAuthNative() override;
	// Called by the extension registry before the shared App is destroyed.
	static void shutdown_all();

	godot::Error initialize();
	// Providers: anonymous, game_center, apple, google, play_games_platform.
	// `p_link` keeps the User captured before platform UI starts.
	int64_t sign_in(const godot::String &p_provider, bool p_link);
	int64_t sign_in_play_games(const godot::String &p_server_auth_code, bool p_link);
	int64_t sign_in_with_custom_token(const godot::String &p_token);
	int64_t sign_in_with_email(const godot::String &p_email, const godot::String &p_password);
	// Same providers as sign_in() except anonymous; the credential must be the signed-in user's.
	int64_t reauthenticate(const godot::String &p_provider);
	int64_t reauthenticate_with_email(const godot::String &p_email, const godot::String &p_password);
	// Firebase provider ID from the user's `providers`, e.g. "google.com".
	int64_t unlink_provider(const godot::String &p_provider_id);
	// Optional String keys display_name and photo_url; "" clears one.
	int64_t update_profile(const godot::Dictionary &p_profile);
	int64_t reload_user();
	void sign_out();
	int64_t delete_user();
	// Apple accounts: Sign in with Apple once more, then revoke its tokens.
	// Succeeds with false and no UI when the user has no apple.com provider.
	int64_t revoke_apple_token();
	int64_t get_id_token(bool p_force_refresh);
	godot::Dictionary current_user() const;

protected:
	static void _bind_methods();

private:
	void OnAuthStateChanged(firebase::auth::Auth *p_auth) override;
	// Runs `p_request` with the signed-in user, or fails with kNoUser.
	int64_t start_with_user(const std::function<void(firebase::auth::User &, Completion)> &p_request);
	int64_t start_platform_credential(const std::string &p_provider, CredentialUse p_use);
	int64_t start_email_credential(const std::string &p_email, const std::string &p_password, CredentialUse p_use);

	void shutdown();
	std::shared_ptr<AuthSession> session;
	firebase::auth::Auth *auth = nullptr;
};

} // namespace godot_firebase
