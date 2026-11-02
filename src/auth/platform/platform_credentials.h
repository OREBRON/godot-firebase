#pragma once

#include <functional>
#include <string>

#include <firebase/auth/credential.h>

#include "../../core/outcome.h"

namespace godot_firebase {

struct PlatformCredential {
	bool ok = false;
	firebase::auth::Credential credential;
	int error_code = 0;
	std::string error_message;
	// Sign in with Apple only; revoke_apple_token() needs it.
	std::string apple_authorization_code;
};

struct PlatformCredentialOptions {
	std::string google_web_client_id;
	std::string google_ios_client_id;
};

using CredentialCallback = std::function<void(PlatformCredential)>;

// Runs the platform's sign-in UI (game_center/apple/google/play_games_platform)
// and returns a Firebase credential. `done` may run on any thread.
void request_platform_credential(const std::string &provider, const PlatformCredentialOptions &options, CredentialCallback done);

// Revokes the signed-in user's Apple tokens with a fresh authorization code
// (iOS FirebaseAuth). Succeeds with true.
void revoke_apple_token(const std::string &authorization_code, Completion done);

void clear_platform_credential_state();

} // namespace godot_firebase
