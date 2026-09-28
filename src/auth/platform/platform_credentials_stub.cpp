// Platforms without a native sign-in UI (desktop development builds).

#include "platform_credentials.h"

#include "../outcome.h"

namespace godot_firebase {

void request_platform_credential(const std::string &provider, CredentialCallback done) {
	PlatformCredential result;
	result.error_code = kUnsupported;
	result.error_message = provider + " sign-in is not supported on this platform";
	done(result);
}

} // namespace godot_firebase
