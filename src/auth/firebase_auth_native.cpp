#include "firebase_auth_native.h"

#include <utility>

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

namespace {

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

// Takes Auth, not the module: Auth lives as long as the App, while the module
// may be freed before the platform sign-in UI answers.
void sign_in_with_credential(firebase::auth::Auth *p_auth, const Credential &p_credential, bool p_link, Completion p_done) {
	if (!p_link) {
		complete_when_done(p_auth->SignInAndRetrieveDataWithCredential(p_credential), std::move(p_done), user_of);
		return;
	}
	User user = p_auth->current_user();
	if (!user.is_valid()) {
		p_done(Outcome::failure(kNoUser, "link needs a signed-in user"));
		return;
	}
	complete_when_done(user.LinkWithCredential(p_credential), std::move(p_done), user_of);
}

} // namespace

FirebaseAuthNative::~FirebaseAuthNative() {
	if (auth) {
		auth->RemoveAuthStateListener(this);
	}
}

godot::Error FirebaseAuthNative::initialize() {
	if (auth) {
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
	auth->AddAuthStateListener(this);
	return godot::OK;
}

int64_t FirebaseAuthNative::sign_in(const String &p_provider, bool p_link) {
	const std::string provider = to_std(p_provider);
	return start([this, provider, p_link](Completion done) {
		if (auth == nullptr) {
			done(unavailable());
		} else if (provider == "anonymous") {
			if (p_link) {
				done(Outcome::failure(kInvalidArgument, "cannot link to an anonymous account"));
			} else {
				complete_when_done(auth->SignInAnonymously(), std::move(done), user_of);
			}
		} else {
			firebase::auth::Auth *app_auth = auth;
			request_platform_credential(provider, [app_auth, p_link, done](PlatformCredential result) {
				if (result.ok) {
					sign_in_with_credential(app_auth, result.credential, p_link, done);
				} else {
					done(Outcome::failure(result.error_code, to_godot(result.error_message)));
				}
			});
		}
	});
}

int64_t FirebaseAuthNative::sign_in_play_games(const String &p_server_auth_code, bool p_link) {
	const std::string code = to_std(p_server_auth_code);
	return start([this, code, p_link](Completion done) {
		if (auth == nullptr) {
			done(unavailable());
		} else if (code.empty()) {
			done(Outcome::failure(kInvalidArgument, "Play Games server auth code is required"));
#ifdef __ANDROID__
		} else {
			sign_in_with_credential(auth, firebase::auth::PlayGamesAuthProvider::GetCredential(code.c_str()), p_link, done);
#else
		} else {
			done(Outcome::failure(kUnsupported, "Play Games sign-in requires Android"));
#endif
		}
	});
}

void FirebaseAuthNative::sign_out() {
	if (auth) {
		auth->SignOut();
	}
}

int64_t FirebaseAuthNative::delete_user() {
	return start_with_user([](User &user, Completion done) {
		complete_when_done(user.Delete(), std::move(done));
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
	return auth ? to_dictionary(auth->current_user()) : Dictionary();
}

int64_t FirebaseAuthNative::start_with_user(const std::function<void(User &, Completion)> &p_request) {
	return start([this, &p_request](Completion done) {
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
	emit_deferred("auth_state_changed", godot::Array::make(to_dictionary(p_auth->current_user())));
}

void FirebaseAuthNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseAuthNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("sign_in", "provider", "link"), &FirebaseAuthNative::sign_in);
	godot::ClassDB::bind_method(D_METHOD("sign_in_play_games", "server_auth_code", "link"), &FirebaseAuthNative::sign_in_play_games);
	godot::ClassDB::bind_method(D_METHOD("sign_out"), &FirebaseAuthNative::sign_out);
	godot::ClassDB::bind_method(D_METHOD("delete_user"), &FirebaseAuthNative::delete_user);
	godot::ClassDB::bind_method(D_METHOD("get_id_token", "force_refresh"), &FirebaseAuthNative::get_id_token);
	godot::ClassDB::bind_method(D_METHOD("current_user"), &FirebaseAuthNative::current_user);
	ADD_SIGNAL(godot::MethodInfo("auth_state_changed", godot::PropertyInfo(godot::Variant::DICTIONARY, "user")));
}

} // namespace godot_firebase
