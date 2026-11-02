// iOS sign-in UIs: Game Center (GameKit) and Sign in with Apple
// (AuthenticationServices). Both hand their result to Firebase as a credential.

#include "platform_credentials.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>
#import <FirebaseAuth/FirebaseAuth.h>
// FIRAuth's interface lives in the Swift header; it needs FIRAuthInterop first (as in the C++ SDK).
#import <FirebaseAuthInterop/FIRAuthInterop.h>
#import <FirebaseAuth/FirebaseAuth-Swift.h>
#import <GameKit/GameKit.h>
#import <GoogleSignIn/GoogleSignIn.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <firebase/auth.h>
#include <atomic>

#include "../../core/ios_presenter.h"
#include "../../core/outcome.h"

using godot_firebase::key_window;
using godot_firebase::top_view_controller;

using godot_firebase::CredentialCallback;
using godot_firebase::PlatformCredential;

namespace {
std::atomic<uint64_t> platform_generation{0};

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

// The C++ SDK (13.13–14.1) passes accessToken:nil to a selector whose Swift
// parameter is non-optional, so the request carries an empty access_token and
// Firebase rejects every Apple token. Route that case to the selector without
// an access token. Remove once firebase/firebase-cpp-sdk#1954 is fixed.
void route_empty_oauth_access_token() {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SEL selector = @selector(credentialWithProviderID:IDToken:rawNonce:accessToken:);
		Method method = class_getClassMethod(FIROAuthProvider.class, selector);
		if (!method) return;
		using Factory = FIROAuthCredential *(*)(id, SEL, NSString *, NSString *, NSString *, NSString *);
		Factory original = reinterpret_cast<Factory>(method_getImplementation(method));
		IMP replacement = imp_implementationWithBlock(^FIROAuthCredential *(id provider_class, NSString *provider, NSString *id_token, NSString *raw_nonce, NSString *access_token) {
			if (access_token.length == 0) {
				return [FIROAuthProvider credentialWithProviderID:provider IDToken:id_token rawNonce:raw_nonce];
			}
			return original(provider_class, selector, provider, id_token, raw_nonce, access_token);
		});
		method_setImplementation(method, replacement);
	});
}

std::string describe(NSError *error, const char *fallback) {
	return error ? std::string(error.localizedDescription.UTF8String) : std::string(fallback);
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

void sign_in_with_game_center(CredentialCallback done, uint64_t generation) {
	GKLocalPlayer *player = GKLocalPlayer.localPlayer;
	if (player.isAuthenticated) {
		game_center_credential(done);
		return;
	}
	// GameKit may call the handler several times (UI shown, then result).
	__block bool finished = false;
	player.authenticateHandler = ^(UIViewController *view_controller, NSError *error) {
		if (finished || platform_generation.load() != generation) {
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

// Godot 4.7 exposes addService: on its app delegate. Register at runtime after
// engine startup, avoiding the +load ordering issue and an engine-header ABI dependency.
@interface NSObject (GodotFirebaseServiceRegistration)
+ (void)addService:(NSObject<UIApplicationDelegate, UIWindowSceneDelegate> *)service;
@end

@interface GodotFirebaseGoogleURLService : NSObject <UIApplicationDelegate, UIWindowSceneDelegate>
@end
@implementation GodotFirebaseGoogleURLService
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
	return [GIDSignIn.sharedInstance handleURL:url];
}
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
	for (UIOpenURLContext *context in contexts) [GIDSignIn.sharedInstance handleURL:context.URL];
}
@end

namespace {
bool register_google_url_service() {
	static bool registered = false;
	if (registered) return true;
	Class delegate_class = NSClassFromString(@"GDTApplicationDelegate");
	if (!delegate_class || ![delegate_class respondsToSelector:@selector(addService:)]) return false;
	[delegate_class addService:[GodotFirebaseGoogleURLService new]];
	registered = true;
	return true;
}

bool has_url_scheme(NSString *scheme) {
	for (NSDictionary *url_type in NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"]) {
		if ([url_type[@"CFBundleURLSchemes"] containsObject:scheme]) return true;
	}
	return false;
}

void sign_in_with_google(const godot_firebase::PlatformCredentialOptions &options, CredentialCallback done) {
	NSString *client = options.google_ios_client_id.empty() ? NSBundle.mainBundle.infoDictionary[@"GIDClientID"] : [NSString stringWithUTF8String:options.google_ios_client_id.c_str()];
	if (!client.length) {
		NSDictionary *firebase_config = [NSDictionary dictionaryWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"GoogleService-Info" ofType:@"plist"]];
		client = firebase_config[@"CLIENT_ID"];
	}
	if (!client.length) { done(failure(godot_firebase::kInvalidArgument, "firebase/auth/google_ios_client_id is required")); return; }
	NSString *scheme = [[[client componentsSeparatedByString:@"."] reverseObjectEnumerator].allObjects componentsJoinedByString:@"."];
	if (!has_url_scheme(scheme)) { done(failure(godot_firebase::kInvalidArgument, "Google's reversed client ID URL scheme is missing from the export")); return; }
	if (!register_google_url_service()) { done(failure(godot_firebase::kUnavailable, "Godot's iOS URL callback service is unavailable")); return; }
	UIViewController *presenter = top_view_controller();
	if (!presenter) { done(failure(godot_firebase::kUnavailable, "no active iOS presentation window")); return; }
	NSString *server = options.google_web_client_id.empty() ? nil : [NSString stringWithUTF8String:options.google_web_client_id.c_str()];
	GIDSignIn.sharedInstance.configuration = [[GIDConfiguration alloc] initWithClientID:client serverClientID:server];
	[GIDSignIn.sharedInstance signInWithPresentingViewController:presenter completion:^(GIDSignInResult *result, NSError *error) {
		if (error) {
			done(failure(error.code == kGIDSignInErrorCodeCanceled ? godot_firebase::kCancelled : godot_firebase::kUnavailable, "Google sign-in failed or was cancelled"));
			return;
		}
		NSString *token = result.user.idToken.tokenString;
		if (!token.length) { done(failure(godot_firebase::kUnavailable, "Google did not return an identity token")); return; }
		done(success(firebase::auth::GoogleAuthProvider::GetCredential(token.UTF8String, result.user.accessToken.tokenString.UTF8String)));
	}];
}
} // namespace

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
	if (active_apple_sign_in == self) active_apple_sign_in = nil;
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
	ASAuthorizationAppleIDCredential *apple = (ASAuthorizationAppleIDCredential *)authorization.credential;
	NSString *token = apple.identityToken ? [[NSString alloc] initWithData:apple.identityToken encoding:NSUTF8StringEncoding] : nil;
	if (!token) {
		[self finish:failure(godot_firebase::kUnavailable, "Apple did not return an identity token")];
		return;
	}
	route_empty_oauth_access_token();
	PlatformCredential result = success(firebase::auth::OAuthProvider::GetCredential("apple.com", token.UTF8String, self.rawNonce.UTF8String, nullptr));
	NSString *code = apple.authorizationCode ? [[NSString alloc] initWithData:apple.authorizationCode encoding:NSUTF8StringEncoding] : nil;
	if (code) result.apple_authorization_code = code.UTF8String;
	[self finish:result];
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
	const bool cancelled = error.code == ASAuthorizationErrorCanceled;
	[self finish:failure(cancelled ? godot_firebase::kCancelled : static_cast<int>(error.code), describe(error, "Sign in with Apple failed"))];
}

@end

namespace godot_firebase {

void request_platform_credential(const std::string &p_provider, const PlatformCredentialOptions &p_options, CredentialCallback callback) {
	// Blocks capture C++ references by reference; copy before going async.
	const std::string provider = p_provider;
	const PlatformCredentialOptions options = p_options;
	const uint64_t generation = platform_generation.load();
	CredentialCallback done = [generation, callback](PlatformCredential result) {
		if (platform_generation.load() == generation) callback(std::move(result));
	};
	dispatch_async(dispatch_get_main_queue(), ^{
		if (platform_generation.load() != generation) return;
		if (provider == "google") {
			sign_in_with_google(options, done);
		} else if (provider == "game_center") {
			sign_in_with_game_center(done, generation);
		} else if (provider == "apple") {
			if (active_apple_sign_in) {
				done(failure(kBusy, "Sign in with Apple is already running"));
				return;
			}
			active_apple_sign_in = [GodotFirebaseAppleSignIn new];
			[active_apple_sign_in startWithCallback:done];
		} else {
			done(failure(kUnsupported, provider + " sign-in is not supported on iOS"));
		}
	});
}

// The C++ SDK has no revokeToken; on iOS it wraps this same default FIRAuth.
void revoke_apple_token(const std::string &authorization_code, Completion done) {
	NSString *code = [NSString stringWithUTF8String:authorization_code.c_str()];
	[[FIRAuth auth] revokeTokenWithAuthorizationCode:code completion:^(NSError *error) {
		done(error ? Outcome::failure(static_cast<int>(error.code), to_godot(describe(error, "Apple token revocation failed"))) : Outcome::success(true));
	}];
}

void clear_platform_credential_state() {
	++platform_generation;
	dispatch_async(dispatch_get_main_queue(), ^{
		[GIDSignIn.sharedInstance signOut];
		GKLocalPlayer.localPlayer.authenticateHandler = nil;
	});
}

} // namespace godot_firebase
