#pragma once

#include <firebase/storage.h>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Cloud Storage. Method names match addons/firebase/storage/firebase_storage_mock.gd.
// Metadata results are {path, name, size, content_type, updated}; `updated` is Unix milliseconds.
class FirebaseStorageNative : public FirebaseModuleNative {
	GDCLASS(FirebaseStorageNative, FirebaseModuleNative)

public:
	godot::Error initialize();
	int64_t upload_bytes(const godot::String &p_path, const godot::PackedByteArray &p_data, const godot::String &p_content_type);
	int64_t download_bytes(const godot::String &p_path, int64_t p_max_size);
	int64_t get_download_url(const godot::String &p_path);
	int64_t get_metadata(const godot::String &p_path);
	int64_t delete_file(const godot::String &p_path);

protected:
	static void _bind_methods();

private:
	// Runs `p_request` with the file at `p_path`, or fails for an invalid path.
	int64_t start_with_file(const godot::String &p_path, const std::function<void(firebase::storage::StorageReference, Completion)> &p_request);

	firebase::storage::Storage *storage = nullptr;
};

} // namespace godot_firebase
