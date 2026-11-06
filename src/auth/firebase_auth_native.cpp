#include "firebase_auth_native.h"

#include <utility>
#include <mutex>
#include <set>
#include <vector>

#include <godot_cpp/classes/project_settings.hpp>

#include <godot_cpp/core/class_db.hpp>

#include "../core/firebase_app_native.h"
#include "platform/platform_credentials.h"

using firebase::Future;
using firebase::auth::AuthResult;
using firebase::auth::Credential;
using firebase::auth::User;
using godot::D_METHOD;
using godot::Dictionary;
using godot::String;

namespace godot_firebase {

struct AuthOperation {
	uint64_t generation = 0;
	User source_user;
	std::string source_uid;
	Completion done;
	bool sdk_started = false;
	bool cancelled = false;
};

struct AuthSession {
	std::recursive_mutex mutex;
	firebase::auth::Auth *auth = nullptr;
	std::shared_ptr<AuthOperation> active;
	uint64_t generation = 0;
};

namespace {
std::set<FirebaseAuthNative *> live_modules;
// The C++ SDK returns one Auth per shared App and the platform UI bridge is
// process-wide. Only one wrapper may own that session. A pending SDK callback
// retains this lease even if its wrapper is destroyed.
std::weak_ptr<AuthSession> auth_session_owner;

void cancel_operation(const std::shared_ptr<AuthSession> &session) {
	++session->generation;
	if (!session->active) return;
	auto operation = session->active;
	operation->cancelled = true;
	auto done = std::exchange(operation->done, Completion{});
	// An SDK sign-in cannot be cancelled. Keep the slot until it settles, so a
	// late SDK response cannot overwrite a newer sign-in. Platform UI is safe to
	// discard immediately because its callback has not called Firebase yet.
	if (!operation->sdk_started) {
		operation->source_user = User();
		session->active.reset();
	}
	if (done) done(Outcome::failure(kCancelled, "auth operation was cancelled"));
}

std::shared_ptr<AuthOperation> begin_operation(const std::shared_ptr<AuthSession> &session, bool link, Completion done) {
	if (!session->auth) {
		done(Outcome::failure(kUnavailable, "FirebaseAuthNative is not initialized"));
		return {};
	}
	if (session->active) {
		done(Outcome::failure(kBusy, "another auth operation is running"));
		return {};
	}
	User source = session->auth->current_user();
	if (link && !source.is_valid()) {
		done(Outcome::failure(kNoUser, "link needs a signed-in user"));
		return {};
	}
	auto operation = std::make_shared<AuthOperation>();
	operation->source_user = source;
	operation->source_uid = source.is_valid() ? source.uid() : "";
	operation->generation = session->generation;
	operation->done = std::move(done);
	session->active = operation;
	return operation;
}

Completion finish_operation(const std::shared_ptr<AuthSession> &session, const std::shared_ptr<AuthOperation> &operation) {
	return [session, operation](Outcome result) {
		std::lock_guard<std::recursive_mutex> lock(session->mutex);
		if (session->active != operation) return;
		if (operation->cancelled && session->auth && result.ok) {
			// Only the cancelled SDK operation owns this slot; sign-out must win.
			session->auth->SignOut();
		}
		session->active.reset();
		auto done = std::exchange(operation->done, Completion{});
		if (done) done(std::move(result));
	};
}

// A cancelled SDK sign-in that still succeeds is signed out by finish_operation.
// The user it briefly signs in must not reach GDScript as a state change.
bool compensating_sign_out_pending(const std::shared_ptr<AuthSession> &session) {
	return session->active && session->active->cancelled && session->active->sdk_started;
}

PlatformCredentialOptions credential_options() {
	PlatformCredentialOptions options;
	auto *settings = godot::ProjectSettings::get_singleton();
	options.google_web_client_id = to_std(settings->get_setting("firebase/auth/google_web_client_id", ""));
	options.google_ios_client_id = to_std(settings->get_setting("firebase/auth/google_ios_client_id", ""));
	return options;
}


Dictionary to_dictionary(const User &p_user) {
	Dictionary user;
	if (!p_user.is_valid()) {
		return user;
	}
	user["uid"] = to_godot(p_user.uid());
	user["email"] = to_godot(p_user.email());
	user["display_name"] = to_godot(p_user.display_name());
	user["is_anonymous"] = p_user.is_anonymous();
	return user;
}

godot::Variant user_of(const Future<AuthResult> &p_future) {
	return to_dictionary(p_future.result()->user);
}

Outcome unavailable() {
	return Outcome::failure(kUnavailable, "FirebaseAuthNative is not initialized");
}

// After platform UI: only the user signed in before it may continue to the SDK.
bool start_sdk_after_platform_ui(const std::shared_ptr<AuthSession> &session, const std::shared_ptr<AuthOperation> &operation) {
	if (!session->auth || session->active != operation || operation->generation != session->generation) return false;
	const User current = session->auth->current_user();
	const std::string uid = current.is_valid() ? current.uid() : "";
	if (uid != operation->source_uid) {
		cancel_operation(session);
		return false;
	}
	operation->sdk_started = true;
	return true;
}

void sign_in_with_credential(const std::shared_ptr<AuthSession> &session, const std::shared_ptr<AuthOperation> &operation, const Credential &credential, bool link) {
	std::lock_guard<std::recursive_mutex> lock(session->mutex);
	if (!start_sdk_after_platform_ui(session, operation)) return;
	auto done = finish_operation(session, operation);
	if (link) {
		// The User captured BEFORE the UI is the only allowed link target.
		complete_when_done(operation->source_user.LinkWithCredential(credential), std::move(done), user_of);
	} else {
		complete_when_done(session->auth->SignInAndRetrieveDataWithCredential(credential), std::move(done), user_of);
	}
}

void revoke_with_apple_code(const std::shared_ptr<AuthSession> &session, const std::shared_ptr<AuthOperation> &operation, const std::string &code) {
	std::lock_guard<std::recursive_mutex> lock(session->mutex);
	if (start_sdk_after_platform_ui(session, operation)) revoke_apple_token(code, finish_operation(session, operation));
}

bool has_provider(const User &user, const std::string &provider) {
	for (const auto &info : user.provider_data()) {
		if (info.provider_id() == provider) return true;
	}
	return false;
}

} // namespace

FirebaseAuthNative::FirebaseAuthNative() : session(std::make_shared<AuthSession>()) {
	live_modules.insert(this);
}

FirebaseAuthNative::~FirebaseAuthNative() {
	shutdown();
	live_modules.erase(this);
}

void FirebaseAuthNative::shutdown() {
	firebase::auth::Auth *previous = auth;
	{
		std::lock_guard<std::recursive_mutex> lock(session->mutex);
		cancel_operation(session);
		// A disposed wrapper may leave an uncancellable SDK sign-in in flight.
		// Its completion retains the session lease and must still be able to
		// sign out a late success before any replacement wrapper can initialize.
		if (!session->active) session->auth = nullptr;
		auth = nullptr;
	}
	if (previous) {
		previous->RemoveAuthStateListener(this);
		clear_platform_credential_state();
	}
}

void FirebaseAuthNative::shutdown_all() {
	for (auto *module : std::vector<FirebaseAuthNative *>(live_modules.begin(), live_modules.end())) module->shutdown();
	// This includes a session retained only by an SDK completion after its
	// wrapper was freed. Revoke every Auth/User reference before App deletion.
	if (auto owner = auth_session_owner.lock()) {
		std::lock_guard<std::recursive_mutex> lock(owner->mutex);
		cancel_operation(owner);
		owner->auth = nullptr;
		if (owner->active) owner->active->source_user = User();
		owner->active.reset();
	}
	clear_platform_credential_state();
}

godot::Error FirebaseAuthNative::initialize() {
	if (auth || !auth_session_owner.expired()) {
		return godot::ERR_ALREADY_IN_USE;
	}
	firebase::App *app = FirebaseAppNative::get_app();
	if (app == nullptr) {
		return godot::ERR_UNCONFIGURED;
	}
	firebase::InitResult result = firebase::kInitResultSuccess;
	auth = firebase::auth::Auth::GetAuth(app, &result);
	if (auth == nullptr || result != firebase::kInitResultSuccess) {
		auth = nullptr;
		return godot::ERR_CANT_CREATE;
	}
	session->auth = auth;
	auth_session_owner = session;
	auth->AddAuthStateListener(this);
	return godot::OK;
}

int64_t FirebaseAuthNative::sign_in(const String &p_provider, bool p_link) {
	const std::string provider = to_std(p_provider);
	const auto options = credential_options();
	return start([this, provider, p_link, options](Completion done) {
		const auto state = session;
		std::lock_guard<std::recursive_mutex> lock(state->mutex);
		if (provider == "anonymous" && p_link) {
			done(Outcome::failure(kInvalidArgument, "cannot link to an anonymous account"));
			return;
		}
		auto operation = begin_operation(state, p_link, std::move(done));
		if (!operation) return;
		if (provider == "anonymous") {
			operation->sdk_started = true;
			complete_when_done(auth->SignInAnonymously(), finish_operation(state, operation), user_of);
			return;
		}
		request_platform_credential(provider, options, [state, operation, p_link](PlatformCredential result) {
			if (result.ok) {
				sign_in_with_credential(state, operation, result.credential, p_link);
			} else {
				finish_operation(state, operation)(Outcome::failure(result.error_code, to_godot(result.error_message)));
			}
		});
	});
}

int64_t FirebaseAuthNative::sign_in_play_games(const String &p_server_auth_code, bool p_link) {
	const std::string code = to_std(p_server_auth_code);
	return start([this, code, p_link](Completion done) {
		if (code.empty()) {
			done(Outcome::failure(kInvalidArgument, "Play Games server auth code is required"));
			return;
		}
#ifdef __ANDROID__
		std::lock_guard<std::recursive_mutex> lock(session->mutex);
		auto operation = begin_operation(session, p_link, std::move(done));
		if (operation) sign_in_with_credential(session, operation, firebase::auth::PlayGamesAuthProvider::GetCredential(code.c_str()), p_link);
#else
		done(Outcome::failure(kUnsupported, "Play Games sign-in requires Android"));
#endif
	});
}

void FirebaseAuthNative::sign_out() {
	std::lock_guard<std::recursive_mutex> lock(session->mutex);
	if (!auth) return; // An uninitialized wrapper cannot cancel another UI flow.
	cancel_operation(session);
	auth->SignOut();
	clear_platform_credential_state();
}

int64_t FirebaseAuthNative::delete_user() {
	return start_with_user([](User &user, Completion done) {
		complete_when_done(user.Delete(), std::move(done));
	});
}

int64_t FirebaseAuthNative::revoke_apple_token() {
	const auto options = credential_options();
	return start([this, options](Completion done) {
		const auto state = session;
		std::lock_guard<std::recursive_mutex> lock(state->mutex);
		if (auth && !auth->current_user().is_valid()) {
			done(Outcome::failure(kNoUser, "no signed-in user"));
			return;
		}
		auto operation = begin_operation(state, false, std::move(done));
		if (!operation) return;
		if (!has_provider(operation->source_user, "apple.com")) {
			finish_operation(state, operation)(Outcome::success(false));
			return;
		}
		request_platform_credential("apple", options, [state, operation](PlatformCredential result) {
			if (!result.ok) {
				finish_operation(state, operation)(Outcome::failure(result.error_code, to_godot(result.error_message)));
			} else if (result.apple_authorization_code.empty()) {
				finish_operation(state, operation)(Outcome::failure(kUnavailable, "Apple did not return an authorization code"));
			} else {
				revoke_with_apple_code(state, operation, result.apple_authorization_code);
			}
		});
	});
}

int64_t FirebaseAuthNative::get_id_token(bool p_force_refresh) {
	return start_with_user([p_force_refresh](User &user, Completion done) {
		complete_when_done(user.GetToken(p_force_refresh), std::move(done), [](const Future<std::string> &future) {
			return godot::Variant(to_godot(*future.result()));
		});
	});
}

Dictionary FirebaseAuthNative::current_user() const {
	std::lock_guard<std::recursive_mutex> lock(session->mutex);
	return auth ? to_dictionary(auth->current_user()) : Dictionary();
}

int64_t FirebaseAuthNative::start_with_user(const std::function<void(User &, Completion)> &p_request) {
	return start([this, &p_request](Completion done) {
		std::lock_guard<std::recursive_mutex> lock(session->mutex);
		if (auth == nullptr) {
			done(unavailable());
			return;
		}
		User user = auth->current_user();
		if (!user.is_valid()) {
			done(Outcome::failure(kNoUser, "no signed-in user"));
			return;
		}
		p_request(user, std::move(done));
	});
}

void FirebaseAuthNative::OnAuthStateChanged(firebase::auth::Auth *p_auth) {
	std::lock_guard<std::recursive_mutex> lock(session->mutex);
	if (!session->auth) return;
	const User user = p_auth->current_user();
	const std::string uid = user.is_valid() ? user.uid() : "";
	if (user.is_valid() && compensating_sign_out_pending(session)) return;
	if (session->active && !session->active->sdk_started && session->active->source_uid != uid) cancel_operation(session);
	emit_deferred("auth_state_changed", godot::Array::make(to_dictionary(user)));
}

void FirebaseAuthNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseAuthNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("sign_in", "provider", "link"), &FirebaseAuthNative::sign_in);
	godot::ClassDB::bind_method(D_METHOD("sign_in_play_games", "server_auth_code", "link"), &FirebaseAuthNative::sign_in_play_games);
	godot::ClassDB::bind_method(D_METHOD("sign_out"), &FirebaseAuthNative::sign_out);
	godot::ClassDB::bind_method(D_METHOD("delete_user"), &FirebaseAuthNative::delete_user);
	godot::ClassDB::bind_method(D_METHOD("revoke_apple_token"), &FirebaseAuthNative::revoke_apple_token);
	godot::ClassDB::bind_method(D_METHOD("get_id_token", "force_refresh"), &FirebaseAuthNative::get_id_token);
	godot::ClassDB::bind_method(D_METHOD("current_user"), &FirebaseAuthNative::current_user);
	ADD_SIGNAL(godot::MethodInfo("auth_state_changed", godot::PropertyInfo(godot::Variant::DICTIONARY, "user")));
}

} // namespace godot_firebase
