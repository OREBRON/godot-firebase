extends FirebaseTest
## Native to_godot_key (src/core/outcome.h) accepts a server key only if
## String::utf8 re-encodes it to the same bytes. The desktop build loads stubs,
## so this checks that rule with the engine's own decoder (get_string_from_utf8
## uses the same one): spoofing keys fail it, ordinary keys pass.


func _run() -> void:
	var role := "role".to_utf8_buffer()
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF]) + role
	var nul := role + PackedByteArray([0, 0x78])
	for spoof in [bom, nul]:
		check(spoof.get_string_from_utf8() == "role", "engine still merges %s into role; drop this test if the decoder changed" % spoof)
		check(not _round_trips(spoof), "spoofing key %s is rejected" % spoof)
	for key in ["role", "", "çğış", "ключ", "鍵", "🔑", "a b.c-d_e", "role﻿"]:
		check(_round_trips(key.to_utf8_buffer()), "key %s is accepted" % key)


func _round_trips(bytes: PackedByteArray) -> bool:
	return bytes.get_string_from_utf8().to_utf8_buffer() == bytes
