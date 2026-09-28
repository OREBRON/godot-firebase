class_name FirebaseResult
extends RefCounted
## Outcome of one Firebase request.
##
## Firebase error codes (AuthError, firestore::Error) are positive. The
## negative codes below come from this addon; the native backend uses the same
## values in src/outcome.h.

const ERR_INVALID_ARGUMENT := -1
const ERR_UNSUPPORTED := -2
const ERR_UNAVAILABLE := -3
const ERR_NO_USER := -4
const ERR_CANCELLED := -5

var ok := false
var value: Variant = null
var error_code := 0
var error_message := ""


static func success(result_value: Variant = null) -> FirebaseResult:
	var result := FirebaseResult.new()
	result.ok = true
	result.value = result_value
	return result


static func failure(code: int, message: String) -> FirebaseResult:
	var result := FirebaseResult.new()
	result.error_code = code
	result.error_message = message
	return result
