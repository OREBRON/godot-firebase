#pragma once
#import <UIKit/UIKit.h>

namespace godot_firebase {
// Call on the main thread. Godot 4.7 hosts its view controller in SwiftUI, so
// platform UI is presented from the topmost controller of the key window.
UIWindow *key_window();
UIViewController *top_view_controller();
} // namespace godot_firebase
