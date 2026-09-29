#pragma once

#include <firebase/auth.h>
#include <godot_cpp/variant/dictionary.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Firebase Authentication. Method names match addons/godot_firebase/auth/firebase_auth_mock.gd.
// Users are {uid, email, display_name, is_anonymous}; {} means signed out.
class FirebaseAuthNative : public FirebaseModuleNative, private firebase::auth::AuthStateListener {
	GDCLASS(FirebaseAuthNative, FirebaseModuleNative)

public:
	~FirebaseAuthNative() override;

	godot::Error initialize();
	// `p_provider`: "anonymous", "game_center" or "apple". `p_link` keeps the current uid.
	int64_t sign_in(const godot::String &p_provider, bool p_link);
	int64_t sign_in_play_games(const godot::String &p_server_auth_code, bool p_link);
	void sign_out();
	int64_t delete_user();
	int64_t get_id_token(bool p_force_refresh);
	godot::Dictionary current_user() const;

protected:
	static void _bind_methods();

private:
	void OnAuthStateChanged(firebase::auth::Auth *p_auth) override;
	// Runs `p_request` with the signed-in user, or fails with kNoUser.
	int64_t start_with_user(const std::function<void(firebase::auth::User &, Completion)> &p_request);

	firebase::auth::Auth *auth = nullptr;
};

} // namespace godot_firebase
