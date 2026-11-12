#!/usr/bin/env python3
"""Execute Auth lifecycle control flow from production against a tiny SDK stub.

No Firebase/device behavior is simulated as acceptance evidence. The functions
are extracted so changing shutdown/cancellation in production changes this test;
renaming them requires updating the explicitly bounded extraction list.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "src/auth/firebase_auth_native.cpp").read_text()
def function(start, text=source):
 pos=text.index(start)
 brace=text.index('{',pos)
 level=1
 end=brace+1
 while level:
  level += (text[end]=='{')-(text[end]=='}')
  end+=1
 return text[pos:end]
structs=source[source.index('struct AuthOperation {'):source.index('namespace {',source.index('struct AuthOperation {'))]
helpers='\n'.join(function(n) for n in ['void cancel_operation(', 'Completion finish_operation(', 'bool compensating_sign_out_pending('])
helpers+='\n'+function('template <typename T, typename Map>', (ROOT / "src/core/outcome.h").read_text())
methods='\n'.join(function(n) for n in ['void FirebaseAuthNative::shutdown()', 'void FirebaseAuthNative::shutdown_all()', 'void FirebaseAuthNative::sign_out()'])
prelude=r"""
#include <functional>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>
#include <utility>
#include <cassert>
#include <iostream>
namespace firebase { namespace auth {
struct Auth { int signouts=0; void SignOut(){++signouts;} void RemoveAuthStateListener(void*){}; };
}}
namespace firebase {
enum FutureStatus { kFutureStatusComplete, kFutureStatusPending, kFutureStatusInvalid };
// The invalid Future the SDK's User methods return without a signed-in user:
// its OnCompletion() drops the callback.
template <typename T> struct Future {
 FutureStatus status() const {return kFutureStatusInvalid;}
 int error() const {return -1;}
 const char* error_message() const {return nullptr;}
 void OnCompletion(std::function<void(const Future&)>) const {}
};
}
namespace godot { struct Variant {}; struct String { static const char* utf8(const char* text) {return text;} }; }
struct User {};
struct Outcome { bool ok; int error_code=0; static Outcome success(godot::Variant) {return {true};} static Outcome failure(int code,const char*) {return {false,code};} };
using Completion=std::function<void(Outcome)>;
constexpr int kUnavailable=-3;
constexpr int kCancelled=-5;
int platform_clears=0;
void clear_platform_credential_state() {++platform_clears;}
"""
cls=r"""
class FirebaseAuthNative {
public:
 std::shared_ptr<AuthSession> session=std::make_shared<AuthSession>();
 firebase::auth::Auth* auth=nullptr;
 void shutdown(); void sign_out(); static void shutdown_all();
};
std::set<FirebaseAuthNative*> live_modules;
std::weak_ptr<AuthSession> auth_session_owner;
"""
tests=r"""
void pending_sdk_completion(bool sign_out_first, bool destroy_app, bool live_at_app_shutdown) {
 firebase::auth::Auth sdk;
 auto backend=std::make_unique<FirebaseAuthNative>();
 backend->auth=&sdk; backend->session->auth=&sdk;
 auth_session_owner=backend->session;
 auto operation=std::make_shared<AuthOperation>();
 operation->sdk_started=true;
 int completed=0;
 operation->done=[&](Outcome result){assert(!result.ok); ++completed;};
 backend->session->active=operation;
 Completion finish=finish_operation(backend->session,operation);
 std::shared_ptr<AuthSession> session=backend->session;
 assert(!compensating_sign_out_pending(session)); // a running sign-in reports its user
 if(sign_out_first) {
  backend->sign_out();
  assert(compensating_sign_out_pending(session)); // its late user is stale
 }
 if(live_at_app_shutdown) {
  live_modules.insert(backend.get());
  FirebaseAuthNative::shutdown_all();
  live_modules.erase(backend.get());
 } else {
  backend->shutdown();
 }
 backend.reset();
 assert(completed==1);
 assert(!auth_session_owner.expired());
 if(destroy_app && !live_at_app_shutdown) FirebaseAuthNative::shutdown_all();
 finish({true});
 assert(completed==1);
 assert(!compensating_sign_out_pending(session));
 // A disposed wrapper still compensates the uncancellable SDK success. An App
 // shutdown revokes that pointer, so even an orphan must never call Auth again.
 const int expected_signouts=(sign_out_first ? 1 : 0)+(destroy_app ? 0 : 1);
 assert(sdk.signouts==expected_signouts);
 finish={}; operation.reset(); session.reset();
 assert(auth_session_owner.expired());
}
void uninitialized_wrapper_does_not_clear_owner() {
 firebase::auth::Auth sdk;
 FirebaseAuthNative owner;
 owner.auth=&sdk; owner.session->auth=&sdk;
 auth_session_owner=owner.session;
 auto pending=std::make_shared<AuthOperation>();
 owner.session->active=pending;
 const int clears_before=platform_clears;
 FirebaseAuthNative other;
 other.sign_out(); other.shutdown();
 assert(platform_clears==clears_before);
 assert(sdk.signouts==0 && owner.session->active==pending);
 owner.shutdown();
 assert(platform_clears==clears_before+1);
}
void invalid_sdk_future_releases_slot() {
 firebase::auth::Auth sdk;
 auto session=std::make_shared<AuthSession>();
 session->auth=&sdk;
 auto operation=std::make_shared<AuthOperation>();
 operation->sdk_started=true;
 int code=0;
 operation->done=[&](Outcome result){assert(!result.ok); code=result.error_code;};
 session->active=operation;
 {
  std::lock_guard<std::recursive_mutex> lock(session->mutex); // as the sign-in call sites hold it
  complete_when_done(firebase::Future<void>(), finish_operation(session,operation), [](const firebase::Future<void>&){return godot::Variant();});
 }
 assert(code==kUnavailable);
 assert(!session->active); // the next sign-in is not busy
}
int main() {
 pending_sdk_completion(true,false,false);
 pending_sdk_completion(false,false,false);
 pending_sdk_completion(true,true,false);
 pending_sdk_completion(false,true,true);
 uninitialized_wrapper_does_not_clear_owner();
 invalid_sdk_future_releases_slot();
 std::cout << "Auth lifecycle state checks passed (SDK stub, not device evidence)\n";
}
"""

class AuthLifecycleStateTest(unittest.TestCase):
    def test_production_cancellation_and_shutdown(self):
        with tempfile.TemporaryDirectory(prefix="firebase-auth-state-") as directory:
            cpp = Path(directory) / "auth_state.cpp"
            binary = Path(directory) / "auth_state"
            cpp.write_text(prelude + structs + cls + helpers + methods + tests)
            subprocess.run([os.environ.get("CXX", "c++"), "-std=c++17", str(cpp), "-o", str(binary)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Auth lifecycle state checks passed", result.stdout)

if __name__ == "__main__":
    unittest.main()
