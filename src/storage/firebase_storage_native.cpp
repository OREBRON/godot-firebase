#include "firebase_storage_native.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <memory>
#include <unordered_set>
#include <utility>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "../core/firebase_app_native.h"

using firebase::Future;
using firebase::storage::Controller;
using firebase::storage::Metadata;
using firebase::storage::StorageListResult;
using firebase::storage::StorageReference;
using godot::D_METHOD;
using godot::Dictionary;
using godot::PackedByteArray;
using godot::PackedStringArray;
using godot::String;
using godot::Variant;

namespace godot_firebase {

namespace {

// FirebaseStorage.MAX_DOWNLOAD: download_bytes() allocates max_size bytes up front.
constexpr int64_t kMaxDownload = 100 * 1024 * 1024;
// FirebaseStorage.MAX_LIST_RESULTS: the SDKs reject larger pages, iOS by throwing.
constexpr int64_t kMaxListResults = 1000;

// Same rule as FirebaseStorage.is_file_path().
bool is_file_path(const String &p_path) {
	return !p_path.is_empty() && !p_path.begins_with("/") && !p_path.ends_with("/") && !p_path.contains("//");
}

// FirebaseStorage sends local files as absolute OS paths. The SDKs read them as
// file:// URLs; iOS uploads accept nothing else.
std::string file_url(const String &p_local_path) {
	return to_std("file://" + p_local_path.uri_encode().replace("%2F", "/"));
}

String text_or_empty(const char *p_text) {
	return p_text ? String::utf8(p_text) : String();
}

bool is_text(const Variant &p_value) {
	return p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME;
}

// Sets the content type of an upload; false when it would be cut at a NUL.
bool set_content_type(const String &p_content_type, Metadata &r_metadata) {
	const std::string content_type = to_std(p_content_type);
	if (content_type.find('\0') != std::string::npos) {
		return false;
	}
	if (!content_type.empty()) {
		r_metadata.set_content_type(content_type.c_str());
	}
	return true;
}

bool set_custom_metadata(const Dictionary &p_values, std::map<std::string, std::string> &r_custom) {
	const godot::Array keys = p_values.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const Variant &key = keys[i];
		const Variant &value = p_values[key];
		if (!is_text(key) || value.get_type() != Variant::STRING) {
			return false;
		}
		r_custom[to_std(key)] = to_std(value);
	}
	return true;
}

// Same rule as FirebaseStorage.validate_metadata(). Sets only the given keys, so
// UpdateMetadata() keeps the others.
bool set_metadata_update(const Dictionary &p_values, Metadata &r_metadata) {
	const godot::Array keys = p_values.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const Variant &key = keys[i];
		const Variant &value = p_values[key];
		const String name = is_text(key) ? String(key) : String();
		if (name == "custom_metadata" && value.get_type() == Variant::DICTIONARY) {
			if (!set_custom_metadata(value, *r_metadata.custom_metadata())) {
				return false;
			}
		} else if (name == "content_type" && value.get_type() == Variant::STRING) {
			r_metadata.set_content_type(to_std(value).c_str());
		} else if (name == "cache_control" && value.get_type() == Variant::STRING) {
			r_metadata.set_cache_control(to_std(value).c_str());
		} else {
			return false;
		}
	}
	return true;
}

Variant metadata_of(const Future<Metadata> &p_future) {
	const Metadata &metadata = *p_future.result();
	Dictionary result;
	result["path"] = text_or_empty(metadata.path());
	result["name"] = text_or_empty(metadata.name());
	result["size"] = metadata.size_bytes();
	result["content_type"] = text_or_empty(metadata.content_type());
	result["cache_control"] = text_or_empty(metadata.cache_control());
	Dictionary custom;
	if (const std::map<std::string, std::string> *values = metadata.custom_metadata()) {
		for (const auto &[key, value] : *values) {
			String godot_key;
			if (to_godot_key(key, godot_key)) {
				custom[godot_key] = to_godot(value);
			}
		}
	}
	result["custom_metadata"] = custom;
	result["updated"] = metadata.updated_time();
	return result;
}

// Android's full_path() may start with "/"; listed paths are used again as file paths.
PackedStringArray paths_of(const std::vector<StorageReference> &p_references) {
	PackedStringArray paths;
	for (StorageReference reference : p_references) { // full_path() is not const.
		paths.push_back(to_godot(reference.full_path()).trim_prefix("/"));
	}
	return paths;
}

Variant list_of(const Future<StorageListResult> &p_future) {
	const StorageListResult &list = *p_future.result();
	Dictionary result;
	result["files"] = paths_of(list.items());
	result["folders"] = paths_of(list.prefixes());
	result["next_page_token"] = to_godot(list.next_page_token());
	return result;
}

} // namespace

namespace {
std::unordered_set<FirebaseStorageNative *> active_modules;
}

FirebaseStorageNative::FirebaseStorageNative() {
	active_modules.insert(this);
	// Answers reach the main thread through this signal; the transfer is over then.
	connect("request_completed", callable_mp(this, &FirebaseStorageNative::forget_transfer).unbind(4));
}

FirebaseStorageNative::~FirebaseStorageNative() {
	active_modules.erase(this);
}

void FirebaseStorageNative::shutdown_all() {
	// The Storage instance belongs to the App; later requests fail as unavailable.
	// Controllers refer to it too, so they go first.
	for (FirebaseStorageNative *module : active_modules) {
		module->transfers.clear();
		module->storage = nullptr;
	}
}

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

int64_t FirebaseStorageNative::start_transfer(const String &p_path, const Transfer &p_request) {
	// On the heap: iOS assigns the task to it from a main-queue block.
	auto controller = std::make_unique<Controller>();
	const int64_t id = start_with_file(p_path, [&p_request, &controller](StorageReference file, Completion done) {
		p_request(std::move(file), controller.get(), std::move(done));
	});
	transfers[id] = std::move(controller);
	return id;
}

void FirebaseStorageNative::forget_transfer(int64_t p_id) {
	transfers.erase(p_id);
}

int64_t FirebaseStorageNative::upload_bytes(const String &p_path, const PackedByteArray &p_data, const String &p_content_type) {
	return start_transfer(p_path, [&p_data, &p_content_type](StorageReference file, Controller *controller, Completion done) {
		Metadata metadata;
		if (!set_content_type(p_content_type, metadata)) {
			done(Outcome::failure(kInvalidArgument, "content_type must not contain NUL"));
			return;
		}
		// PutBytes reads the buffer until its future completes.
		auto buffer = std::make_shared<std::vector<uint8_t>>(p_data.ptr(), p_data.ptr() + p_data.size());
		complete_when_done(file.PutBytes(buffer->data(), buffer->size(), metadata, nullptr, controller), std::move(done), [buffer](const Future<Metadata> &future) {
			return metadata_of(future);
		});
	});
}

int64_t FirebaseStorageNative::upload_file(const String &p_path, const String &p_local_path, const String &p_content_type) {
	return start_transfer(p_path, [&p_local_path, &p_content_type](StorageReference file, Controller *controller, Completion done) {
		Metadata metadata;
		if (!set_content_type(p_content_type, metadata)) {
			done(Outcome::failure(kInvalidArgument, "content_type must not contain NUL"));
		} else if (!p_local_path.begins_with("/")) {
			done(Outcome::failure(kInvalidArgument, "local_path must be absolute: " + p_local_path));
		} else {
			complete_when_done(file.PutFile(file_url(p_local_path).c_str(), metadata, nullptr, controller), std::move(done), metadata_of);
		}
	});
}

int64_t FirebaseStorageNative::download_bytes(const String &p_path, int64_t p_max_size) {
	return start_transfer(p_path, [p_max_size](StorageReference file, Controller *controller, Completion done) {
		if (p_max_size <= 0 || p_max_size > kMaxDownload) {
			done(Outcome::failure(kInvalidArgument, "max_size must be in 1.." + String::num_int64(kMaxDownload)));
			return;
		}
		// GetBytes writes into the buffer until its future completes. It stays uninitialized so the
		// main thread does not zero max_size bytes; only the received bytes are written and copied.
		const size_t size = static_cast<size_t>(p_max_size);
		std::shared_ptr<uint8_t[]> buffer(new uint8_t[size]);
		complete_when_done(file.GetBytes(buffer.get(), size, nullptr, controller), std::move(done), [buffer, size](const Future<size_t> &future) {
			PackedByteArray bytes;
			bytes.resize(static_cast<int64_t>(std::min(*future.result(), size)));
			// A failed resize leaves the array empty, so memcpy uses bytes.size().
			if (!bytes.is_empty()) {
				memcpy(bytes.ptrw(), buffer.get(), static_cast<size_t>(bytes.size()));
			}
			return Variant(bytes);
		});
	});
}

int64_t FirebaseStorageNative::download_file(const String &p_path, const String &p_local_path) {
	return start_transfer(p_path, [&p_local_path](StorageReference file, Controller *controller, Completion done) {
		if (!p_local_path.begins_with("/")) {
			done(Outcome::failure(kInvalidArgument, "local_path must be absolute: " + p_local_path));
			return;
		}
		complete_when_done(file.GetFile(file_url(p_local_path).c_str(), nullptr, controller), std::move(done), [](const Future<size_t> &future) {
			return Variant(static_cast<int64_t>(*future.result()));
		});
	});
}

Dictionary FirebaseStorageNative::get_transfer_progress(int64_t p_id) const {
	Dictionary progress;
	const auto transfer = transfers.find(p_id);
	if (transfer != transfers.end() && transfer->second->is_valid()) {
		progress["bytes_transferred"] = transfer->second->bytes_transferred();
		progress["total_bytes"] = transfer->second->total_byte_count();
	}
	return progress;
}

void FirebaseStorageNative::cancel_transfer(int64_t p_id) {
	const auto transfer = transfers.find(p_id);
	if (transfer != transfers.end() && transfer->second->is_valid()) {
		transfer->second->Cancel();
	}
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

int64_t FirebaseStorageNative::update_metadata(const String &p_path, const Dictionary &p_metadata) {
	return start_with_file(p_path, [&p_metadata](StorageReference file, Completion done) {
		Metadata metadata;
		if (!set_metadata_update(p_metadata, metadata)) {
			done(Outcome::failure(kInvalidArgument, "metadata keys are content_type and cache_control with String values and custom_metadata with string keys and values"));
			return;
		}
		complete_when_done(file.UpdateMetadata(metadata), std::move(done), metadata_of);
	});
}

int64_t FirebaseStorageNative::delete_file(const String &p_path) {
	return start_with_file(p_path, [](StorageReference file, Completion done) {
		complete_when_done(file.Delete(), std::move(done));
	});
}

int64_t FirebaseStorageNative::list_files(const String &p_path, int64_t p_max_results, const String &p_page_token) {
	// A folder path follows the file path rule.
	return start_with_file(p_path, [p_max_results, &p_page_token](StorageReference folder, Completion done) {
		if (p_max_results <= 0 || p_max_results > kMaxListResults) {
			done(Outcome::failure(kInvalidArgument, "max_results must be in 1.." + String::num_int64(kMaxListResults)));
			return;
		}
		const std::string token = to_std(p_page_token);
		complete_when_done(folder.List(static_cast<int>(p_max_results), token.empty() ? nullptr : token.c_str()), std::move(done), list_of);
	});
}

void FirebaseStorageNative::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("initialize"), &FirebaseStorageNative::initialize);
	godot::ClassDB::bind_method(D_METHOD("upload_bytes", "path", "data", "content_type"), &FirebaseStorageNative::upload_bytes);
	godot::ClassDB::bind_method(D_METHOD("upload_file", "path", "local_path", "content_type"), &FirebaseStorageNative::upload_file);
	godot::ClassDB::bind_method(D_METHOD("download_bytes", "path", "max_size"), &FirebaseStorageNative::download_bytes);
	godot::ClassDB::bind_method(D_METHOD("download_file", "path", "local_path"), &FirebaseStorageNative::download_file);
	godot::ClassDB::bind_method(D_METHOD("get_transfer_progress", "id"), &FirebaseStorageNative::get_transfer_progress);
	godot::ClassDB::bind_method(D_METHOD("cancel_transfer", "id"), &FirebaseStorageNative::cancel_transfer);
	godot::ClassDB::bind_method(D_METHOD("get_download_url", "path"), &FirebaseStorageNative::get_download_url);
	godot::ClassDB::bind_method(D_METHOD("get_metadata", "path"), &FirebaseStorageNative::get_metadata);
	godot::ClassDB::bind_method(D_METHOD("update_metadata", "path", "metadata"), &FirebaseStorageNative::update_metadata);
	godot::ClassDB::bind_method(D_METHOD("delete_file", "path"), &FirebaseStorageNative::delete_file);
	godot::ClassDB::bind_method(D_METHOD("list_files", "path", "max_results", "page_token"), &FirebaseStorageNative::list_files);
}

} // namespace godot_firebase
