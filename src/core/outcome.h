#pragma once

#include <functional>
#include <utility>

#include <firebase/future.h>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot_firebase {

// Same values as FirebaseResult.ERR_* in addons/firebase/core/firebase_result.gd.
enum AddonError : int {
	kInvalidArgument = -1,
	kUnsupported = -2,
	kUnavailable = -3,
	kNoUser = -4,
	kCancelled = -5,
	kBusy = -6,
};

struct Outcome {
	bool ok = false;
	godot::Variant value;
	int error_code = 0;
	godot::String error_message;

	static Outcome success(const godot::Variant &p_value = godot::Variant()) {
		Outcome outcome;
		outcome.ok = true;
		outcome.value = p_value;
		return outcome;
	}

	static Outcome failure(int p_code, const godot::String &p_message) {
		Outcome outcome;
		outcome.error_code = p_code;
		outcome.error_message = p_message;
		return outcome;
	}
};

// Receives the outcome of one request. May run on any thread.
using Completion = std::function<void(Outcome)>;

inline godot::String to_godot(const std::string &p_text) {
	return godot::String::utf8(p_text.data(), static_cast<int64_t>(p_text.size()));
}

inline std::string to_std(const godot::String &p_text) {
	const godot::CharString utf8 = p_text.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

// Decodes a server-supplied Dictionary key. Godot's decoder drops a leading BOM and stops at NUL,
// so two keys could merge into one; only keys that re-encode to the same bytes are accepted.
// Callers skip rejected keys silently: they run on SDK threads, where src/ has no logging pattern.
inline bool to_godot_key(const std::string &p_text, godot::String &r_key) {
	r_key = to_godot(p_text);
	return to_std(r_key) == p_text;
}

// Container levels decoded from server data, above Firestore's 20 and RTDB's 32.
// Deeper subtrees become null so a hostile payload cannot exhaust the stack.
constexpr int kMaxIncomingDepth = 64;

// Calls `done` when `future` completes; `map` turns the result into a Variant.
template <typename T, typename Map>
void complete_when_done(const firebase::Future<T> &p_future, Completion p_done, Map p_map) {
	// The SDK drops the callback of an invalid future (e.g. a User call with no signed-in user).
	if (p_future.status() == firebase::kFutureStatusInvalid) {
		p_done(Outcome::failure(kUnavailable, "Firebase did not start the request"));
		return;
	}
	p_future.OnCompletion([done = std::move(p_done), map = std::move(p_map)](const firebase::Future<T> &result) {
		if (result.error() != 0) {
			const char *message = result.error_message();
			done(Outcome::failure(result.error(), godot::String::utf8(message ? message : "Firebase request failed")));
			return;
		}
		done(Outcome::success(map(result)));
	});
}

inline void complete_when_done(const firebase::Future<void> &p_future, Completion p_done) {
	complete_when_done(p_future, std::move(p_done), [](const firebase::Future<void> &) { return godot::Variant(); });
}

} // namespace godot_firebase
