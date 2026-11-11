#!/usr/bin/env python3
"""Run the native key, path and name guards on tests/fixtures/guard_cases.json.

The guard definitions are copied from src/ and built with the host C++ compiler
against stand-ins for the few godot-cpp String operations they use.
test_guard_cases.gd runs the same table through the GDScript validators, so a
rule changed on only one side fails one of the two tests. Value conversion,
query validation and SDK behavior need godot-cpp in a running engine or a
device; they are not covered here.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CASES = json.loads((ROOT / "tests/fixtures/guard_cases.json").read_text(encoding="utf-8"))
# Production definitions, by file and leading text, in dependency order.
GUARDS = {
	"src/database/firebase_database_native.cpp": ["constexpr int kMaxDepth", "bool is_valid_key(", "bool is_valid_path(", "bool is_readable_path("],
	"src/firestore/value_convert.cpp": ["bool is_string(", "bool is_reserved_segment(", "bool is_reserved_field_name(", "int segment_count(", "bool is_document_path(", "bool is_collection_path(", "bool is_field_path("],
	"src/firestore/firebase_firestore_native.cpp": ["bool is_document_id("],
	"src/storage/firebase_storage_native.cpp": ["bool is_file_path("],
	"src/analytics/firebase_analytics_native.cpp": ["String validate_name(", "String validate_property("],
}
STAND_INS = r"""
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

namespace godot {
struct PackedStringArray;
// UTF-8 bytes, as to_std() returns them; length() and [] count code points like Godot.
struct String {
	std::string utf8;
	String() = default;
	String(const char *p_text) : utf8(p_text) {}
	explicit String(std::string p_text) : utf8(std::move(p_text)) {}
	std::u32string code_points() const {
		std::u32string codes;
		for (size_t i = 0; i < utf8.size();) {
			const unsigned char lead = utf8[i++];
			const int extra = lead < 0xC0 ? 0 : lead < 0xE0 ? 1 : lead < 0xF0 ? 2 : 3;
			char32_t code = lead & (0x7F >> extra);
			for (int k = 0; k < extra; k++) code = code << 6 | (utf8[i++] & 0x3F);
			codes += code;
		}
		return codes;
	}
	bool is_empty() const { return utf8.empty(); }
	int64_t length() const { return code_points().size(); }
	char32_t operator[](int64_t p_index) const { return code_points()[p_index]; }
	bool begins_with(const String &p_text) const { return utf8.compare(0, p_text.utf8.size(), p_text.utf8) == 0; }
	bool ends_with(const String &p_text) const { return utf8.size() >= p_text.utf8.size() && utf8.compare(utf8.size() - p_text.utf8.size(), std::string::npos, p_text.utf8) == 0; }
	bool contains(const String &p_text) const { return utf8.find(p_text.utf8) != std::string::npos; }
	PackedStringArray split(const String &p_delimiter) const;
	bool operator==(const String &p_other) const { return utf8 == p_other.utf8; }
	bool operator!=(const String &p_other) const { return utf8 != p_other.utf8; }
};
struct PackedStringArray : std::vector<String> {
	int64_t size() const { return std::vector<String>::size(); }
	bool has(const String &p_value) const { return std::find(begin(), end(), p_value) != end(); }
};
// Like Godot, keeps empty parts: "" splits into one empty part.
PackedStringArray String::split(const String &p_delimiter) const {
	PackedStringArray parts;
	size_t start = 0;
	for (size_t end; (end = utf8.find(p_delimiter.utf8, start)) != std::string::npos; start = end + p_delimiter.utf8.size()) {
		parts.push_back(String(utf8.substr(start, end - start)));
	}
	parts.push_back(String(utf8.substr(start)));
	return parts;
}
// Every case is a String.
struct Variant {
	enum Type { STRING, STRING_NAME };
	String text;
	Type get_type() const { return STRING; }
	operator String() const { return text; }
};
} // namespace godot

using godot::String;
using godot::Variant;

std::string to_std(const String &p_text) {
	return p_text.utf8;
}
"""
RESULT = r"""
bool result(const std::string &p_kind, const std::string &p_input) {
	const String text(p_input);
	if (p_kind == "database_is_valid_key") return is_valid_key(p_input);
	if (p_kind == "database_is_valid_path") return is_valid_path(text);
	if (p_kind == "database_is_readable_path") return is_readable_path(text);
	if (p_kind == "firestore_is_document_path") return is_document_path(text);
	if (p_kind == "firestore_is_collection_path") return is_collection_path(text);
	if (p_kind == "firestore_is_field_path") return is_field_path(Variant{text});
	if (p_kind == "firestore_is_reserved_field_name") return is_reserved_field_name(text, false);
	if (p_kind == "firestore_is_reserved_field_path") return is_reserved_field_name(text, true);
	if (p_kind == "firestore_is_document_id") return is_document_id(Variant{text});
	if (p_kind == "storage_is_file_path") return is_file_path(text);
	if (p_kind == "analytics_validate_name_40") return validate_name(text, 40).is_empty();
	if (p_kind == "analytics_validate_property") return validate_property(text).is_empty();
	std::cerr << "unknown kind " << p_kind << "\n";
	std::exit(2);
}
"""


def definition(source, start):
	"""The definition that begins with `start`, through its closing brace or semicolon."""
	begin = source.index(start)
	brace = source.find("{", begin)
	semicolon = source.index(";", begin)
	if brace < 0 or semicolon < brace:
		return source[begin:semicolon + 1]
	depth, end = 0, brace
	while True:
		depth += {"{": 1, "}": -1}.get(source[end], 0)
		end += 1
		if depth == 0:
			return source[begin:end]


def cases():
	"""(kind, input, label, expected result) for every case."""
	for kind, results in CASES.items():
		for expected in (True, False):
			for case in results[str(expected).lower()]:
				if isinstance(case, dict):
					yield kind, case["text"] * case["times"], "%r * %d" % (case["text"], case["times"]), expected
				else:
					yield kind, case, repr(case), expected


def literal(text):
	"""A C++ std::string of `text`'s UTF-8 bytes; three-digit octal escapes never run on."""
	data = text.encode("utf-8")
	return 'std::string("%s", %d)' % ("".join("\\%03o" % byte for byte in data), len(data))


class NativeGuardsTest(unittest.TestCase):
	def test_native_guards_match_the_case_table(self):
		table = list(cases())
		guards = [definition((ROOT / path).read_text(encoding="utf-8"), start) for path, starts in GUARDS.items() for start in starts]
		calls = "".join('\tstd::cout << result("%s", %s) << "\\n";\n' % (kind, literal(text)) for kind, text, _, _ in table)
		program = STAND_INS + "\n".join(guards) + RESULT + "int main() {\n" + calls + "}\n"
		with tempfile.TemporaryDirectory(prefix="firebase-guards-") as directory:
			source = Path(directory) / "guards.cpp"
			binary = Path(directory) / "guards"
			source.write_text(program, encoding="utf-8")
			build = subprocess.run([os.environ.get("CXX", "c++"), "-std=c++17", str(source), "-o", str(binary)], capture_output=True, text=True)
			self.assertEqual(build.returncode, 0, build.stderr)
			run = subprocess.run([str(binary)], capture_output=True, text=True)
		self.assertEqual(run.returncode, 0, run.stderr)
		actual = [line == "1" for line in run.stdout.splitlines()]
		self.assertEqual(len(actual), len(table), run.stdout)
		mismatches = ["%s(%s) is %s" % (kind, label, got) for (kind, _, label, expected), got in zip(table, actual) if got != expected]
		if mismatches:
			self.fail("native guards disagree with tests/fixtures/guard_cases.json:\n" + "\n".join(mismatches))


if __name__ == "__main__":
	unittest.main()
