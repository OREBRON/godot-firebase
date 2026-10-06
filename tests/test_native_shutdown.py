#!/usr/bin/env python3
"""Every product releases its App-owned SDK objects before the App is deleted.

Static check of src/register_types.cpp: the SDK instances, listener
registrations and pointers that modules keep are invalid once
FirebaseAppNative::shutdown() deletes the App.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULES = re.search(r"const MODULES: Array\[String\] = \[(.*?)\]", (ROOT / "addons/firebase/core/firebase.gd").read_text()).group(1)
MODULES = re.findall(r'"(\w+)"', MODULES)
SPECIAL_NAMES = {"remote_config": "RemoteConfig"}


class NativeShutdownTest(unittest.TestCase):
	def test_every_module_shuts_down_before_app(self):
		source = (ROOT / "src/register_types.cpp").read_text()
		body = source[source.index("void uninitialize_godot_firebase("):]
		app_shutdown = body.index("FirebaseAppNative::shutdown();")
		for module in MODULES:
			name = SPECIAL_NAMES.get(module, module.capitalize())
			call = "Firebase%sNative::shutdown_all();" % name
			with self.subTest(module=module):
				self.assertIn("static void shutdown_all();", (ROOT / "src" / module / ("firebase_%s_native.h" % module)).read_text())
				self.assertIn(call, body)
				self.assertLess(body.index(call), app_shutdown)


if __name__ == "__main__":
	unittest.main()
