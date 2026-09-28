#pragma once

#include <functional>
#include <string>

#include <firebase/auth/credential.h>

namespace godot_firebase {

struct PlatformCredential {
	bool ok = false;
	firebase::auth::Credential credential;
	int error_code = 0;
	std::string error_message;
};

using CredentialCallback = std::function<void(PlatformCredential)>;

// Runs the platform's own sign-in UI for `provider` ("game_center", "apple")
// and returns a Firebase credential. `done` may run on any thread.
void request_platform_credential(const std::string &provider, CredentialCallback done);

} // namespace godot_firebase
