#include "firebase_storage_native.h"

#include <cstring>
#include <memory>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>

#include "../core/firebase_app_native.h"

using firebase::Future;
using firebase::storage::Metadata;
using firebase::storage::StorageReference;
using godot::D_METHOD;
using godot::Dictionary;
using godot::PackedByteArray;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

// FirebaseStorage.MAX_DOWNLOAD: download_bytes() allocates max_size bytes up front.
constexpr int64_t kMaxDownload = 100 * 1024 * 1024;

// Same rule as FirebaseStorage.is_file_path().
bool is_file_path(const String &p_path) {
	return !p_path.is_empty() && !p_path.begins_with("/") && !p_path.ends_with("/") && !p_path.contains("//");
}

String text_or_empty(const char *p_text) {
	return p_text ? String::utf8(p_text) : String();
}

Variant metadata_of(const Future<Metadata> &p_future) {
	const Metadata &metadata = *p_future.result();
	Dictionary result;
	result["path"] = text_or_empty(metadata.path());
	result["name"] = text_or_empty(metadata.name());
	result["size"] = metadata.size_bytes();
	result["content_type"] = text_or_empty(metadata.content_type());
	result["updated"] = metadata.updated_time();
	return result;
}

} // namespace

godot::Error FirebaseStorageNative::initialize() {
	if (storage) {
		return godot::ERR_ALREADY_IN_USE;
	}
	firebase::App *app = FirebaseAppNative::get_app();
	if (app == nullptr) {
		return godot::ERR_UNCONFIGURED;
	}
	firebase::InitResult result = firebase::kInitResultSuccess;
	storage = firebase::storage::Storage::GetInstance(app, &result);
	if (storage == nullptr || result != firebase::kInitResultSuccess) {
		storage = nullptr;
		return godot::ERR_CANT_CREATE;
	}
	return godot::OK;
}

int64_t FirebaseStorageNative::start_with_file(const String &p_path, const std::function<void(StorageReference, Completion)> &p_request) {
	return start([this, &p_path, &p_request](Completion done) {
		if (storage == nullptr) {
			done(Outcome::failure(kUnavailable, "FirebaseStorageNative is not initialized"));
		} else if (!is_file_path(p_path)) {
			done(Outcome::failure(kInvalidArgument, "not a storage file path: " + p_path));
		} else {
			p_request(storage->GetReference(to_std(p_path)), std::move(done));
		}
	});
}

int64_t FirebaseStorageNative::upload_bytes(const String &p_path, const PackedByteArray &p_data, const String &p_content_type) {
	return start_with_file(p_path, [&p_data, &p_content_type](StorageReference file, Completion done) {
		// PutBytes reads the buffer until its future completes.
		auto buffer = std::make_shared<std::vector<uint8_t>>(p_data.ptr(), p_data.ptr() + p_data.size());
		Metadata metadata;
		const std::string content_type = to_std(p_content_type);
		if (!content_type.empty()) {
			metadata.set_content_type(content_type.c_str());
		}
		complete_when_done(file.PutBytes(buffer->data(), buffer->size(), metadata), std::move(done), [buffer](const Future<Metadata> &future) {
			return metadata_of(future);
		});
	});
}

int64_t FirebaseStorageNative::download_bytes(const String &p_path, int64_t p_max_size) {
	return start_with_file(p_path, [p_max_size](StorageReference file, Completion done) {
		if (p_max_size <= 0 || p_max_size > kMaxDownload) {
			done(Outcome::failure(kInvalidArgument, "max_size must be in 1.." + String::num_int64(kMaxDownload)));
			return;
		}
		// GetBytes writes into the buffer until its future completes.
		auto buffer = std::make_shared<std::vector<uint8_t>>(static_cast<size_t>(p_max_size));
		complete_when_done(file.GetBytes(buffer->data(), buffer->size()), std::move(done), [buffer](const Future<size_t> &future) {
			PackedByteArray bytes;
			bytes.resize(static_cast<int64_t>(*future.result()));
			if (!bytes.is_empty()) {
				memcpy(bytes.ptrw(), buffer->data(), static_cast<size_t>(bytes.size()));
			}
			return Variant(bytes);
		});
	});
}

int64_t FirebaseStorageNative::get_download_url(const String &p_path) {
	return start_with_file(p_path, [](StorageReference file, Completion done) {
		complete_when_done(file.GetDownloadUrl(), std::move(done), [](const Future<std::string> &future) {
			return Variant(to_godot(*future.result()));
		});
	});
}

int64_t FirebaseStorageNative::get_metadata(const String &p_path) {
	return start_with_file(p_path, [](StorageReference file, Completion done) {
		complete_when_done(file.GetMetadata(), std::move(done), metadata_of);
	});
}

int64_t FirebaseStorageNative::delete_file(const String &p_path) {
	return start_with_file(p_path, [](StorageReference file, Completion done) {
		complete_when_done(file.Delete(), std::move(done));
	});
}

void FirebaseStorageNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseStorageNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("upload_bytes", "path", "data", "content_type"), &FirebaseStorageNative::upload_bytes);
	godot::ClassDB::bind_method(D_METHOD("download_bytes", "path", "max_size"), &FirebaseStorageNative::download_bytes);
	godot::ClassDB::bind_method(D_METHOD("get_download_url", "path"), &FirebaseStorageNative::get_download_url);
	godot::ClassDB::bind_method(D_METHOD("get_metadata", "path"), &FirebaseStorageNative::get_metadata);
	godot::ClassDB::bind_method(D_METHOD("delete_file", "path"), &FirebaseStorageNative::delete_file);
}

} // namespace godot_firebase
