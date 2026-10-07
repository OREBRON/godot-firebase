// Rewarded ads (GoogleMobileAds) and UMP consent for FirebaseAdmobNative.
// Every SDK call, and all state below, stays on the main queue.

#include "admob_platform.h"

#import <GoogleMobileAds/GoogleMobileAds.h>
#import <UserMessagingPlatform/UserMessagingPlatform.h>

#include <atomic>

#include "../../core/ios_presenter.h"

using godot_firebase::Outcome;

namespace {
// FirebaseResult.ERR_INVALID_ARGUMENT and FirebaseAdmob.ERROR_* codes.
constexpr int kErrorInternal = 1;
constexpr int kErrorInvalidRequest = 2;
constexpr int kErrorNetwork = 3;
constexpr int kErrorNoFill = 4;
constexpr int kErrorAppIdMissing = 5;
constexpr int kErrorAdAlreadyUsed = 7;
constexpr int kErrorShowFailed = 8;

// Shutdown increments it; answers of earlier requests are dropped.
std::atomic<int> generation{ 0 };

NSString *ns_string(const godot::String &p_value) {
	const godot::CharString utf8 = p_value.utf8();
	return [[NSString alloc] initWithBytes:utf8.get_data() length:utf8.length() encoding:NSUTF8StringEncoding];
}

godot::String godot_string(NSString *p_value) {
	return p_value ? godot::String::utf8(p_value.UTF8String) : godot::String();
}

NSArray<NSString *> *ns_strings(const godot::Variant &p_value) {
	const godot::PackedStringArray values = p_value;
	NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:values.size()];
	for (int64_t i = 0; i < values.size(); i++) {
		[result addObject:ns_string(values[i])];
	}
	return result;
}

void finish(int64_t p_token, int p_generation, Outcome p_result) {
	if (p_token != 0 && p_generation == generation) {
		godot_firebase::finish_admob_request(p_token, std::move(p_result));
	}
}

Outcome failure(int p_code, const char *p_context, NSError *p_error) {
	godot::String message = p_context;
	if (p_error) {
		message += godot::String(": ") + godot_string(p_error.localizedDescription) + " (" + godot::String::num_int64(p_error.code) + ")";
	}
	return Outcome::failure(p_code, message);
}

NSMutableDictionary<NSNumber *, GADRewardedAd *> *loaded_ads() {
	static NSMutableDictionary<NSNumber *, GADRewardedAd *> *ads = [NSMutableDictionary dictionary];
	return ads;
}

int load_error(NSError *p_error) {
	if (![p_error.domain isEqualToString:GADErrorDomain]) {
		return kErrorInternal;
	}
	switch (p_error.code) {
		case GADErrorInvalidRequest:
		case GADErrorInvalidArgument:
		case GADErrorReceivedInvalidAdString:
			return kErrorInvalidRequest;
		case GADErrorNoFill:
			return kErrorNoFill;
		case GADErrorNetworkError:
		case GADErrorTimeout:
			return kErrorNetwork;
		case GADErrorApplicationIdentifierMissing:
			return kErrorAppIdMissing;
		case GADErrorAdAlreadyUsed:
			return kErrorAdAlreadyUsed;
		default:
			return kErrorInternal;
	}
}

int show_error(NSError *p_error) {
	const bool reused = [p_error.domain isEqualToString:GADErrorDomain] && (p_error.code == GADPresentationErrorCodeAdAlreadyUsed || p_error.code == GADErrorAdAlreadyUsed);
	return reused ? kErrorAdAlreadyUsed : kErrorShowFailed;
}
} // namespace

// Keeps the presented ad and answers its show request when it closes.
@interface GodotFirebaseRewardedDelegate : NSObject <GADFullScreenContentDelegate>
@property(nonatomic, strong) GADRewardedAd *ad;
@property(nonatomic) int64_t adId;
@property(nonatomic) int64_t token;
@property(nonatomic) int generation;
@property(nonatomic) BOOL rewarded;
@end

namespace {
// The ad's delegate is weak; the presented ads' delegates live here.
NSMutableDictionary<NSNumber *, GodotFirebaseRewardedDelegate *> *showing_delegates() {
	static NSMutableDictionary<NSNumber *, GodotFirebaseRewardedDelegate *> *delegates = [NSMutableDictionary dictionary];
	return delegates;
}

void emit(GodotFirebaseRewardedDelegate *p_delegate, const char *p_event) {
	if (p_delegate.generation == generation) {
		godot_firebase::emit_admob_event(p_delegate.adId, p_event);
	}
}

// The ad's events precede the answer of its show request, as native expects.
void finish_show(GodotFirebaseRewardedDelegate *p_delegate, Outcome p_result) {
	[showing_delegates() removeObjectForKey:@(p_delegate.adId)];
	finish(p_delegate.token, p_delegate.generation, std::move(p_result));
}
} // namespace

@implementation GodotFirebaseRewardedDelegate
- (void)adWillPresentFullScreenContent:(id<GADFullScreenPresentingAd>)ad {
	emit(self, "opened");
}

- (void)adDidRecordImpression:(id<GADFullScreenPresentingAd>)ad {
	emit(self, "impression");
}

- (void)adDidRecordClick:(id<GADFullScreenPresentingAd>)ad {
	emit(self, "clicked");
}

- (void)ad:(id<GADFullScreenPresentingAd>)ad didFailToPresentFullScreenContentWithError:(NSError *)error {
	emit(self, "failed_to_show");
	finish_show(self, failure(show_error(error), "Rewarded ad failed to show", error));
}

- (void)adDidDismissFullScreenContent:(id<GADFullScreenPresentingAd>)ad {
	emit(self, "closed");
	GADAdReward *reward = self.ad.adReward;
	godot::Dictionary result;
	result["rewarded"] = static_cast<bool>(self.rewarded);
	result["reward_type"] = self.rewarded ? godot_string(reward.type) : godot::String();
	result["reward_amount"] = self.rewarded ? static_cast<int64_t>(reward.amount.longLongValue) : int64_t(0);
	finish_show(self, Outcome::success(result));
}
@end

namespace {
godot::Dictionary consent_result() {
	UMPConsentInformation *consent = UMPConsentInformation.sharedInstance;
	godot::Dictionary result;
	result["can_request_ads"] = static_cast<bool>(consent.canRequestAds);
	switch (consent.consentStatus) {
		case UMPConsentStatusRequired:
			result["consent_status"] = "required";
			break;
		case UMPConsentStatusNotRequired:
			result["consent_status"] = "not_required";
			break;
		case UMPConsentStatusObtained:
			result["consent_status"] = "obtained";
			break;
		default:
			result["consent_status"] = "unknown";
			break;
	}
	result["privacy_options_required"] = consent.privacyOptionsRequirementStatus == UMPPrivacyOptionsRequirementStatusRequired;
	return result;
}

void answer_consent(int64_t p_token, int p_generation, NSError *p_error) {
	if (!p_error) {
		finish(p_token, p_generation, Outcome::success(consent_result()));
		return;
	}
	const bool network = [p_error.domain isEqualToString:UMPErrorDomain] && (p_error.code == UMPRequestErrorCodeNetwork || p_error.code == UMPFormErrorCodeTimeout);
	finish(p_token, p_generation, failure(network ? kErrorNetwork : kErrorInternal, "Consent failed", p_error));
}

// UMP: update the consent information every launch, then show the form if required.
void request_consent(const godot::Dictionary &p_options, int64_t p_token, int p_generation) {
	const bool debug = !p_options.is_empty();
	const godot::String geography = p_options.get("debug_geography", "");
	const UMPDebugGeography debug_geography = geography == "eea" ? UMPDebugGeographyEEA : geography == "other" ? UMPDebugGeographyOther : geography == "regulated_us_state" ? UMPDebugGeographyRegulatedUSState : UMPDebugGeographyDisabled;
	NSArray<NSString *> *test_devices = p_options.has("test_device_hashed_ids") ? ns_strings(p_options["test_device_hashed_ids"]) : nil;
	dispatch_async(dispatch_get_main_queue(), ^{
		UMPRequestParameters *parameters = [[UMPRequestParameters alloc] init];
		if (debug) {
			UMPDebugSettings *settings = [[UMPDebugSettings alloc] init];
			settings.geography = debug_geography;
			settings.testDeviceIdentifiers = test_devices;
			parameters.debugSettings = settings;
		}
		[UMPConsentInformation.sharedInstance requestConsentInfoUpdateWithParameters:parameters completionHandler:^(NSError *error) {
			if (error) {
				answer_consent(p_token, p_generation, error);
				return;
			}
			[UMPConsentForm loadAndPresentIfRequiredFromViewController:godot_firebase::top_view_controller() completionHandler:^(NSError *form_error) {
				answer_consent(p_token, p_generation, form_error);
			}];
		}];
	});
}

void show_privacy_options(int64_t p_token, int p_generation) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus != UMPPrivacyOptionsRequirementStatusRequired) {
			answer_consent(p_token, p_generation, nil);
			return;
		}
		[UMPConsentForm presentPrivacyOptionsFormFromViewController:godot_firebase::top_view_controller() completionHandler:^(NSError *error) {
			answer_consent(p_token, p_generation, error);
		}];
	});
}

// A new configuration replaces the previous one; absent keys use SDK defaults.
void set_request_configuration(const godot::Dictionary &p_config, int64_t p_token, int p_generation) {
	NSArray<NSString *> *devices = p_config.has("test_device_ids") ? ns_strings(p_config["test_device_ids"]) : nil;
	const godot::String rating = p_config.get("max_ad_content_rating", "");
	GADMaxAdContentRating max_rating = rating == "G" ? GADMaxAdContentRatingGeneral : rating == "PG" ? GADMaxAdContentRatingParentalGuidance : rating == "T" ? GADMaxAdContentRatingTeen : rating == "MA" ? GADMaxAdContentRatingMatureAudience : nil;
	const godot::String age = p_config.get("age_restricted_treatment", "");
	const GADAgeRestrictedTreatment treatment = age == "child" ? GADAgeRestrictedTreatmentChild : age == "teen" ? GADAgeRestrictedTreatmentTeen : GADAgeRestrictedTreatmentUnspecified;
	dispatch_async(dispatch_get_main_queue(), ^{
		GADRequestConfiguration *configuration = GADMobileAds.sharedInstance.requestConfiguration;
		configuration.testDeviceIdentifiers = devices;
		configuration.maxAdContentRating = max_rating;
		configuration.ageRestrictedTreatment = treatment;
		finish(p_token, p_generation, Outcome::success());
	});
}

void load_rewarded(int64_t p_ad_id, NSString *p_ad_unit_id, int64_t p_token, int p_generation) {
	dispatch_async(dispatch_get_main_queue(), ^{
		// Without GADApplicationIdentifier the SDK raises an exception and the app terminates.
		if (![NSBundle.mainBundle objectForInfoDictionaryKey:@"GADApplicationIdentifier"]) {
			finish(p_token, p_generation, Outcome::failure(kErrorAppIdMissing, "GADApplicationIdentifier is missing from Info.plist; set firebase/admob_app_id in the export preset"));
			return;
		}
		static bool started = false;
		if (!started) {
			started = true;
			[GADMobileAds.sharedInstance startWithCompletionHandler:nil];
		}
		[GADRewardedAd loadWithAdUnitID:p_ad_unit_id request:[GADRequest request] completionHandler:^(GADRewardedAd *ad, NSError *error) {
			if (p_generation != generation) {
				return;
			}
			if (error || !ad) {
				finish(p_token, p_generation, failure(error ? load_error(error) : kErrorInternal, "Rewarded ad failed to load", error));
				return;
			}
			loaded_ads()[@(p_ad_id)] = ad;
			finish(p_token, p_generation, Outcome::success());
		}];
	});
}

void show_rewarded(int64_t p_ad_id, NSString *p_user_id, NSString *p_custom_data, int64_t p_token, int p_generation) {
	dispatch_async(dispatch_get_main_queue(), ^{
		GADRewardedAd *ad = loaded_ads()[@(p_ad_id)];
		[loaded_ads() removeObjectForKey:@(p_ad_id)];
		if (!ad) {
			finish(p_token, p_generation, Outcome::failure(godot_firebase::kInvalidArgument, "Unknown rewarded ad"));
			return;
		}
		if (p_user_id.length > 0 || p_custom_data.length > 0) {
			GADServerSideVerificationOptions *options = [[GADServerSideVerificationOptions alloc] init];
			options.userIdentifier = p_user_id;
			options.customRewardString = p_custom_data;
			ad.serverSideVerificationOptions = options;
		}
		GodotFirebaseRewardedDelegate *delegate = [[GodotFirebaseRewardedDelegate alloc] init];
		delegate.ad = ad;
		delegate.adId = p_ad_id;
		delegate.token = p_token;
		delegate.generation = p_generation;
		showing_delegates()[@(p_ad_id)] = delegate;
		ad.fullScreenContentDelegate = delegate;
		UIViewController *presenter = godot_firebase::top_view_controller();
		NSError *error = nil;
		if (![ad canPresentFromRootViewController:presenter error:&error]) {
			emit(delegate, "failed_to_show");
			finish_show(delegate, failure(show_error(error), "Rewarded ad cannot be shown", error));
			return;
		}
		__weak GodotFirebaseRewardedDelegate *weak_delegate = delegate;
		[ad presentFromRootViewController:presenter userDidEarnRewardHandler:^{
			GodotFirebaseRewardedDelegate *earned = weak_delegate;
			if (earned) {
				earned.rewarded = YES;
				emit(earned, "reward_earned");
			}
		}];
	});
}
} // namespace

namespace godot_firebase {
godot::Error initialize_admob_platform() {
	return godot::OK;
}

void dispatch_admob(const godot::String &p_operation, const godot::Dictionary &p_payload, int64_t p_token) {
	const int current = generation;
	const int64_t ad_id = p_payload.get("ad_id", 0);
	if (p_operation == "request_consent") {
		request_consent(p_payload, p_token, current);
	} else if (p_operation == "show_privacy_options") {
		show_privacy_options(p_token, current);
	} else if (p_operation == "reset_consent") {
		dispatch_async(dispatch_get_main_queue(), ^{
			[UMPConsentInformation.sharedInstance reset];
			finish(p_token, current, Outcome::success());
		});
	} else if (p_operation == "set_request_configuration") {
		set_request_configuration(p_payload, p_token, current);
	} else if (p_operation == "load_rewarded") {
		load_rewarded(ad_id, ns_string(p_payload.get("ad_unit_id", "")), p_token, current);
	} else if (p_operation == "show_rewarded") {
		show_rewarded(ad_id, ns_string(p_payload.get("user_id", "")), ns_string(p_payload.get("custom_data", "")), p_token, current);
	} else if (p_operation == "release_rewarded") {
		dispatch_async(dispatch_get_main_queue(), ^{
			[loaded_ads() removeObjectForKey:@(ad_id)];
		});
	} else {
		finish(p_token, current, Outcome::failure(kInvalidArgument, "Unknown AdMob operation"));
	}
}

void shutdown_admob_platform() {
	++generation;
	dispatch_async(dispatch_get_main_queue(), ^{
		[loaded_ads() removeAllObjects];
	});
}
} // namespace godot_firebase
