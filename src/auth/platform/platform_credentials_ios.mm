// iOS sign-in UIs: Game Center (GameKit) and Sign in with Apple
// (AuthenticationServices). Both hand their result to Firebase as a credential.

#include "platform_credentials.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>
#import <GameKit/GameKit.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

#include <firebase/auth.h>

#include "../../core/outcome.h"

using godot_firebase::CredentialCallback;
using godot_firebase::PlatformCredential;

namespace {

PlatformCredential failure(int code, const std::string &message) {
	PlatformCredential result;
	result.error_code = code;
	result.error_message = message;
	return result;
}

PlatformCredential success(const firebase::auth::Credential &credential) {
	PlatformCredential result;
	result.ok = true;
	result.credential = credential;
	return result;
}

std::string describe(NSError *error, const char *fallback) {
	return error ? std::string(error.localizedDescription.UTF8String) : std::string(fallback);
}

UIWindow *key_window() {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow) {
				return window;
			}
		}
	}
	return nil;
}

UIViewController *top_view_controller() {
	UIViewController *controller = key_window().rootViewController;
	while (controller.presentedViewController) {
		controller = controller.presentedViewController;
	}
	return controller;
}

// Random nonce; Apple receives its SHA-256, Firebase the raw value.
NSString *random_nonce() {
	uint8_t bytes[32];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
		return nil;
	}
	NSMutableString *nonce = [NSMutableString stringWithCapacity:sizeof(bytes) * 2];
	for (uint8_t byte : bytes) {
		[nonce appendFormat:@"%02x", byte];
	}
	return nonce;
}

NSString *sha256(NSString *text) {
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (uint8_t byte : digest) {
		[hex appendFormat:@"%02x", byte];
	}
	return hex;
}

void game_center_credential(CredentialCallback done) {
	firebase::auth::GameCenterAuthProvider::GetCredential().OnCompletion(
			[done](const firebase::Future<firebase::auth::Credential> &future) {
				if (future.error() != 0 || future.result() == nullptr) {
					const char *message = future.error_message();
					done(failure(future.error(), message ? message : "Game Center credential failed"));
					return;
				}
				done(success(*future.result()));
			});
}

void sign_in_with_game_center(CredentialCallback done) {
	GKLocalPlayer *player = GKLocalPlayer.localPlayer;
	if (player.isAuthenticated) {
		game_center_credential(done);
		return;
	}
	// GameKit may call the handler several times (UI shown, then result).
	__block bool finished = false;
	player.authenticateHandler = ^(UIViewController *view_controller, NSError *error) {
		if (finished) {
			return;
		}
		if (view_controller) {
			[top_view_controller() presentViewController:view_controller animated:YES completion:nil];
			return;
		}
		finished = true;
		if (!GKLocalPlayer.localPlayer.isAuthenticated) {
			done(failure(godot_firebase::kCancelled, describe(error, "Game Center sign-in was cancelled")));
			return;
		}
		game_center_credential(done);
	};
}

} // namespace

@interface GodotFirebaseAppleSignIn : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding> {
	CredentialCallback _done;
}
@property(nonatomic, copy) NSString *rawNonce;
- (void)startWithCallback:(CredentialCallback)done;
@end

// Keeps the running request alive until ASAuthorizationController answers.
static GodotFirebaseAppleSignIn *active_apple_sign_in = nil;

@implementation GodotFirebaseAppleSignIn

- (void)startWithCallback:(CredentialCallback)done {
	_done = done;
	self.rawNonce = random_nonce();
	if (!self.rawNonce) {
		[self finish:failure(godot_firebase::kUnavailable, "could not create a sign-in nonce")];
		return;
	}
	ASAuthorizationAppleIDRequest *request = [[ASAuthorizationAppleIDProvider new] createRequest];
	request.requestedScopes = @[];
	request.nonce = sha256(self.rawNonce);
	ASAuthorizationController *controller = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[ request ]];
	controller.delegate = self;
	controller.presentationContextProvider = self;
	[controller performRequests];
}

- (void)finish:(PlatformCredential)result {
	CredentialCallback done = std::move(_done);
	active_apple_sign_in = nil;
	if (done) {
		done(result);
	}
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
	return key_window();
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
	if (![authorization.credential isKindOfClass:ASAuthorizationAppleIDCredential.class]) {
		[self finish:failure(godot_firebase::kUnsupported, "unexpected Apple credential type")];
		return;
	}
	NSData *token_data = ((ASAuthorizationAppleIDCredential *)authorization.credential).identityToken;
	NSString *token = token_data ? [[NSString alloc] initWithData:token_data encoding:NSUTF8StringEncoding] : nil;
	if (!token) {
		[self finish:failure(godot_firebase::kUnavailable, "Apple did not return an identity token")];
		return;
	}
	[self finish:success(firebase::auth::OAuthProvider::GetCredential("apple.com", token.UTF8String, self.rawNonce.UTF8String, nullptr))];
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
	const bool cancelled = error.code == ASAuthorizationErrorCanceled;
	[self finish:failure(cancelled ? godot_firebase::kCancelled : static_cast<int>(error.code), describe(error, "Sign in with Apple failed"))];
}

@end

namespace godot_firebase {

void request_platform_credential(const std::string &p_provider, CredentialCallback done) {
	// Blocks capture C++ references by reference; copy before going async.
	const std::string provider = p_provider;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (provider == "game_center") {
			sign_in_with_game_center(done);
		} else if (provider == "apple") {
			if (active_apple_sign_in) {
				done(failure(kInvalidArgument, "Sign in with Apple is already running"));
				return;
			}
			active_apple_sign_in = [GodotFirebaseAppleSignIn new];
			[active_apple_sign_in startWithCallback:done];
		} else {
			done(failure(kUnsupported, provider + " sign-in is not supported on iOS"));
		}
	});
}

} // namespace godot_firebase
