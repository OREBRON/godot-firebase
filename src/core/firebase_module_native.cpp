#include "firebase_module_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using godot::Array;
using godot::PropertyInfo;
using godot::StringName;
using godot::Variant;

namespace godot_firebase {

void FirebaseModuleNative::_bind_methods() {
	ADD_SIGNAL(godot::MethodInfo("request_completed",
			PropertyInfo(Variant::INT, "id"), PropertyInfo(Variant::BOOL, "ok"), PropertyInfo(Variant::NIL, "value"),
			PropertyInfo(Variant::INT, "error_code"), PropertyInfo(Variant::STRING, "error_message")));
}

int64_t FirebaseModuleNative::start(const std::function<void(Completion)> &p_request) {
	const int64_t id = ++next_request_id;
	const uint64_t object_id = get_instance_id();
	p_request([object_id, id](Outcome outcome) {
		emit_deferred_to(object_id, "request_completed", Array::make(id, outcome.ok, outcome.value, outcome.error_code, outcome.error_message));
	});
	return id;
}

void FirebaseModuleNative::emit_deferred(const StringName &p_signal, const Array &p_args) const {
	emit_deferred_to(get_instance_id(), p_signal, p_args);
}

void FirebaseModuleNative::emit_deferred_to(uint64_t p_object_id, const StringName &p_signal, const Array &p_args) {
	callable_mp_static(&FirebaseModuleNative::deliver).call_deferred(p_object_id, p_signal, p_args);
}

void FirebaseModuleNative::deliver(uint64_t p_object_id, const StringName &p_signal, const Array &p_args) {
	godot::Object *object = godot::ObjectDB::get_instance(p_object_id);
	if (object == nullptr) {
		return;
	}
	Array call_args = godot::Array::make(p_signal);
	call_args.append_array(p_args);
	object->callv("emit_signal", call_args);
}

} // namespace godot_firebase
