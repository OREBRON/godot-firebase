extends FirebaseTest
## The mock must return the documents, in the order, that the Firestore SDK does.
## Rules come from firebase-android-sdk core/FieldFilter.java, ArrayContainsFilter.java,
## ArrayContainsAnyFilter.java, InFilter.java, NotInFilter.java, Bound.java, Query.java
## and model/Values.kt.

var db: FirebaseFirestore


func _run() -> void:
	db = mock_firebase({"firestore": FirebaseFirestoreMock.new()}).firestore
	await _type_order_and_filters()
	await _array_contains()
	await _values_within_a_type()
	await _normalized_order()
	await _cursors()


func _type_order_and_filters() -> void:
	await _seed("mixed", {
		"a_null": {"v": null},
		"b_false": {"v": false},
		"c_true": {"v": true},
		"d_nan": {"v": NAN},
		"e_neg": {"v": -1},
		"f_three": {"v": 3},
		"g_three_float": {"v": 3.0},
		"h_float": {"v": 7.5},
		"i_time": {"v": _timestamp(10, 0)},
		"j_text": {"v": "5"},
		"k_bytes": {"v": PackedByteArray([1])},
		"k_reference": {"v": FirebaseValue.document_reference("users/u1")},
		"k_spot": {"v": FirebaseValue.geo_point(0, 0)},
		"l_array": {"v": [3]},
		"m_map": {"v": {"x": 3}},
		"n_missing": {"other": 1},
	})
	var ascending := ["a_null", "b_false", "c_true", "d_nan", "e_neg", "f_three", "g_three_float", "h_float", "i_time", "j_text", "k_bytes", "k_reference", "k_spot", "l_array", "m_map"]
	await _expect("mixed", [], [["v", "asc"]], ascending, "types order null, bool, NaN, number, timestamp, string, bytes, reference, geo point, array, map; missing fields are excluded")
	var descending := ascending.duplicate()
	descending.reverse()
	await _expect("mixed", [], [["v", "desc"]], descending, "descending order reverses values and document IDs")

	await _expect("mixed", [["v", "<", 5]], [], ["e_neg", "f_three", "g_three_float"], "a range filter skips null, booleans and NaN")
	await _expect("mixed", [["v", ">", 5]], [], ["h_float"], "a range filter skips timestamps, strings, bytes, arrays and maps")
	await _expect("mixed", [["v", ">=", "0"]], [], ["j_text"], "a string range only matches strings")
	await _expect("mixed", [["v", ">", false]], [], ["c_true"], "a boolean range only matches booleans")

	await _expect("mixed", [["v", "==", 3.0]], [], ["f_three", "g_three_float"], "== compares ints and floats numerically")
	await _expect("mixed", [["v", "==", null]], [], ["a_null"], "== null matches a stored null, not a missing field")
	await _expect("mixed", [["v", "==", NAN]], [], ["d_nan"], "== NaN matches NaN")

	var not_three := ["b_false", "c_true", "d_nan", "e_neg", "h_float", "i_time", "j_text", "k_bytes", "k_reference", "k_spot", "l_array", "m_map"]
	await _expect("mixed", [["v", "!=", 3]], [], not_three, "!= matches every other type but never null or a missing field")
	await _expect("mixed", [["v", "!=", null]], [], ascending.slice(1), "!= null matches every stored non-null value")
	await _expect("mixed", [["v", "!=", NAN]], [], ascending.filter(func(id): return not id in ["a_null", "d_nan"]), "!= NaN excludes NaN and null")
	await _expect("mixed", [["v", "in", [3.0, "5", null, NAN]]], [], ["a_null", "d_nan", "f_three", "g_three_float", "j_text"], "in uses value equality, including null and NaN")
	var not_in := ["b_false", "c_true", "e_neg", "h_float", "i_time", "k_bytes", "k_reference", "k_spot", "l_array", "m_map"]
	await _expect("mixed", [["v", "not-in", [3, "5", NAN]]], [], not_in, "not-in uses value equality, orders by its field and skips null and missing fields")
	await _expect("mixed", [["v", "not-in", [3, null]]], [], [], "not-in with null in the list matches nothing")


func _array_contains() -> void:
	await _seed("tags", {
		"a": {"t": [1, "x"]},
		"b": {"t": [1.0]},
		"c": {"t": "x"},
		"d": {"t": [{"k": 1}]},
		"e": {"t": PackedByteArray([1])},
	})
	await _expect("tags", [["t", "array-contains", 1]], [], ["a", "b"], "array-contains compares numbers numerically and ignores bytes")
	await _expect("tags", [["t", "array-contains", "x"]], [], ["a"], "array-contains never matches a non-array field")
	await _expect("tags", [["t", "array-contains", {"k": 1.0}]], [], ["d"], "array-contains compares maps by value")
	await _expect("tags", [["t", "array-contains-any", [1, {"k": 1.0}]]], [], ["a", "b", "d"], "array-contains-any matches any listed element by value")
	await _expect("tags", [["t", "array-contains-any", ["x", 7]]], [], ["a"], "array-contains-any never matches a non-array field")


func _values_within_a_type() -> void:
	await _seed("times", {
		"older": {"at": _timestamp(0, 999999000)},
		"early": {"at": _timestamp(253402300799, 1000)},
		"late": {"at": _timestamp(253402300799, 2000)},
	})
	await _expect("times", [], [["at", "asc"]], ["older", "early", "late"], "timestamps order by seconds, then nanoseconds")
	await _expect("times", [["at", ">", _timestamp(253402300799, 1000)]], [], ["late"], "timestamp filters keep microseconds that a float would round away")

	await _seed("numbers", {"int": {"v": 9007199254740993}, "float": {"v": 9007199254740992.0}})
	await _expect("numbers", [["v", ">", 9007199254740992.0]], [], ["int"], "ints compare exactly against floats")
	await _expect("numbers", [["v", "==", 9007199254740992.0]], [], ["float"], "an int is not equal to a float it rounds to")

	await _seed("strings", {"upper": {"v": "Z"}, "lower": {"v": "a"}, "accent": {"v": "é"}, "bmp": {"v": ""}, "astral": {"v": "😀"}})
	await _expect("strings", [], [["v", "asc"]], ["upper", "lower", "accent", "bmp", "astral"], "strings order by UTF-8 bytes, not UTF-16 code units")

	await _seed("bytes", {
		"high": {"v": PackedByteArray([0x80])},
		"low": {"v": PackedByteArray([0x7F])},
		"long": {"v": PackedByteArray([0x01, 0xFF])},
		"short": {"v": PackedByteArray([0x01])},
		"two": {"v": PackedByteArray([0x02])},
	})
	await _expect("bytes", [], [["v", "asc"]], ["short", "long", "two", "low", "high"], "bytes order as unsigned values, then by length")

	await _seed("maps", {
		"a1": {"m": {"a": 1}},
		"a1b2": {"m": {"b": 2, "a": 1}},
		"a2": {"m": {"a": 2}},
		"b0": {"m": {"b": 0}},
		"empty": {"m": {}},
	})
	await _expect("maps", [], [["m", "asc"]], ["empty", "a1", "a1b2", "a2", "b0"], "maps order by sorted keys, then values, then size")
	await _expect("maps", [["m", "==", {"a": 1.0, "b": 2}]], [], ["a1b2"], "map equality ignores key insertion order")

	await _seed("refs", {
		"short": {"r": FirebaseValue.document_reference("a/b")},
		"slash": {"r": FirebaseValue.document_reference("a/b/c/d")},
		"bang": {"r": FirebaseValue.document_reference("a/b!")},
	})
	await _expect("refs", [], [["r", "asc"]], ["short", "slash", "bang"], "references order by path segments, then segment count")
	await _expect("refs", [["r", "==", FirebaseValue.document_reference("a/b")]], [], ["short"], "reference equality compares paths")

	await _seed("spots", {
		"south": {"p": FirebaseValue.geo_point(-10, 50)},
		"west": {"p": FirebaseValue.geo_point(5, -20)},
		"east": {"p": FirebaseValue.geo_point(5, 20)},
	})
	await _expect("spots", [], [["p", "asc"]], ["south", "west", "east"], "geo points order by latitude, then longitude")
	await _expect("spots", [["p", ">", FirebaseValue.geo_point(5, 0)]], [], ["east"], "geo point ranges compare latitude, then longitude")


func _normalized_order() -> void:
	await _seed("players", {
		"p1": {"score": 20, "level": 1, "team": "red"},
		"p2": {"score": 10, "level": 2, "team": "blue"},
		"p3": {"score": 10, "level": 1, "team": "red"},
		"p4": {"score": 30, "level": 3, "team": "blue"},
		"p5": {"level": 5, "team": "red"},
		"p6": {"score": null, "level": 0, "team": "blue"},
	})
	await _expect("players", [["score", ">", 0]], [], ["p2", "p3", "p1", "p4"], "an inequality field orders results before document IDs")
	await _expect("players", [["score", ">", 0]], [], ["p2"], "limit applies after the implicit inequality order", 1)
	await _expect("players", [["score", ">", 0]], [["team", "desc"]], ["p1", "p3", "p4", "p2"], "implicit orders follow the last explicit direction")
	await _expect("players", [["score", ">", 0]], [["score", "desc"]], ["p4", "p1", "p3", "p2"], "document IDs follow the last explicit direction")
	await _expect("players", [["score", ">", 0], ["level", ">", 0]], [], ["p3", "p1", "p2", "p4"], "several inequality fields order by field path")
	await _expect("players", [["__name__", "!=", "p1"]], [["level", "asc"]], ["p6", "p3", "p2", "p4", "p5"], "a document-ID inequality adds no field order")
	await _expect("players", [], [["score", "asc"]], ["p6", "p2", "p3", "p1", "p4"], "order excludes a missing field but keeps a null value")

	await _expect("players", [["__name__", "not-in", ["p1", "p2"]]], [], ["p3", "p4", "p5", "p6"], "not-in on document IDs adds no field order")

	await _seed("paths", {"x": {"a": {"b": 1}, "a-c": 2}, "y": {"a": {"b": 2}, "a-c": 1}})
	await _expect("paths", [["a-c", ">", 0], ["a.b", ">", 0]], [], ["x", "y"], "inequality field paths compare segment by segment")


## Uses the players of _normalized_order(); by score: p6 (null), p2 and p3 (10), p1 (20), p4 (30).
func _cursors() -> void:
	var by_score := [["score", "asc"]]
	await _expect("players", [], by_score, ["p2", "p3", "p1", "p4"], "start_at includes an equal position", 0, {start_at = [10]})
	await _expect("players", [], by_score, ["p1", "p4"], "start_after skips an equal position", 0, {start_after = [10]})
	await _expect("players", [], by_score, ["p6", "p2", "p3", "p1"], "end_at includes an equal position", 0, {end_at = [20]})
	await _expect("players", [], by_score, ["p6", "p2", "p3"], "end_before skips an equal position", 0, {end_before = [20]})
	await _expect("players", [], by_score, ["p2", "p3", "p1"], "a start and an end bound a range", 0, {start_at = [10], end_at = [20.0]})
	await _expect("players", [], [["score", "desc"]], ["p3", "p2", "p6"], "cursors follow a descending order", 0, {start_after = [20]})
	await _expect("players", [["level", ">", 0]], by_score, ["p1", "p4"], "cursors apply with filters", 0, {start_after = [10]})

	var pages := [["score", "asc"], ["__name__", "asc"]]
	await _expect("players", [], pages, ["p6", "p2"], "first page", 2)
	await _expect("players", [], pages, ["p3", "p1"], "the next page starts after the last score and document ID", 2, {start_after = [10, "p2"]})
	await _expect("players", [], pages, ["p4"], "the last page", 2, {start_after = [20, "p1"]})


func _seed(collection: String, documents: Dictionary) -> void:
	var ops: Array = []
	for id in documents:
		ops.append({"op": "set", "path": "%s/%s" % [collection, id], "data": documents[id]})
	check((await db.batch(ops).wait()).ok, "%s fixtures are accepted" % collection)


func _expect(collection: String, filters: Array, order_by: Array, expected: Array, message: String, limit := 0, cursor := {}) -> void:
	var result := await db.query(collection, filters, order_by, limit, "default", cursor).wait()
	var ids: Array = result.value.map(func(doc): return doc.id) if result.ok else []
	check(result.ok and ids == expected, "%s: expected %s, got %s" % [message, expected, ids])


func _timestamp(seconds: int, nanos: int) -> Dictionary:
	return {FirebaseValue.TAG: FirebaseValue.TIMESTAMP, "seconds": seconds, "nanos": nanos}
