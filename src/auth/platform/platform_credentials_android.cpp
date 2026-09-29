#include "platform_credentials.h"

#include "../../core/outcome.h"

namespace godot_firebase {

void request_platform_credential(const std::string &provider, CredentialCallback done) {
	PlatformCredential result;
	result.error_code = kUnavailable;
	result.error_message = provider + " sign-in is not supported on Android";
	done(result);
}

} // namespace godot_firebase