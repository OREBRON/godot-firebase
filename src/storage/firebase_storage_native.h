#pragma once

#include <memory>
#include <unordered_map>

#include <firebase/storage.h>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include "../core/firebase_module_native.h"

namespace godot_firebase {

// Cloud Storage. Method names match addons/firebase/storage/firebase_storage_mock.gd.
// Metadata results are {path, name, size, content_type, cache_control, custom_metadata, updated};
// `updated` is Unix milliseconds.
class FirebaseStorageNative : public FirebaseModuleNative {
	GDCLASS(FirebaseStorageNative, FirebaseModuleNative)

public:
	FirebaseStorageNative();
	~FirebaseStorageNative() override;
	// Registry calls this before deleting the shared Firebase App.
	static void shutdown_all();

	// A non-empty `p_emulator_host` ("host:port") uses the Cloud Storage emulator.
	godot::Error initialize(const godot::String &p_emulator_host = "");
	int64_t upload_bytes(const godot::String &p_path, const godot::PackedByteArray &p_data, const godot::String &p_content_type);
	int64_t upload_file(const godot::String &p_path, const godot::String &p_local_path, const godot::String &p_content_type);
	int64_t download_bytes(const godot::String &p_path, int64_t p_max_size);
	int64_t download_file(const godot::String &p_path, const godot::String &p_local_path);
	godot::Dictionary get_transfer_progress(int64_t p_id) const;
	void cancel_transfer(int64_t p_id);
	int64_t get_download_url(const godot::String &p_path);
	int64_t get_metadata(const godot::String &p_path);
	int64_t update_metadata(const godot::String &p_path, const godot::Dictionary &p_metadata);
	int64_t delete_file(const godot::String &p_path);
	int64_t list_files(const godot::String &p_path, int64_t p_max_results, const godot::String &p_page_token);

protected:
	static void _bind_methods();

private:
	using Transfer = std::function<void(firebase::storage::StorageReference, firebase::storage::Controller *, Completion)>;

	// Runs `p_request` with the file at `p_path`, or fails for an invalid path.
	int64_t start_with_file(const godot::String &p_path, const std::function<void(firebase::storage::StorageReference, Completion)> &p_request);
	// Same, with a Controller kept for progress and cancel until the answer reaches the main thread.
	int64_t start_transfer(const godot::String &p_path, const Transfer &p_request);
	void forget_transfer(int64_t p_id);

	firebase::storage::Storage *storage = nullptr;
	// Controllers of unfinished uploads and downloads by request id. Main thread only:
	// Controller is not thread safe.
	std::unordered_map<int64_t, std::unique_ptr<firebase::storage::Controller>> transfers;
};

} // namespace godot_firebase
