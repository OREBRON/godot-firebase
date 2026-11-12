#!/usr/bin/env python3
"""Toolchain versions repeated where tools/versions.env cannot be read match it.

Workflow env:/with: values and the shipped .gdextension cannot source
tools/versions.env, so they repeat its pins. Offline; reads only repository text.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(re.findall(r"^(\w+)=(.*)$", (ROOT / "tools/versions.env").read_text(), re.M))
WORKFLOWS = "\n".join(path.read_text() for path in sorted((ROOT / ".github/workflows").glob("*.yml")))


class ToolchainPinsTest(unittest.TestCase):
	def test_workflows_install_the_pinned_android_sdk(self):
		installs = re.findall(r"^\s+packages: '(.*)'$", WORKFLOWS, re.M)
		self.assertTrue(installs, "android-actions/setup-android packages")
		for packages in installs:
			with self.subTest(packages=packages):
				self.assertEqual(packages, installs[0], "every workflow builds Android with the same SDK packages")
				self.assertIn("platforms;android-" + ENV["ANDROID_PLATFORM_VERSION"], packages.split())
				self.assertIn("ndk;" + ENV["ANDROID_NDK_VERSION"], packages.split())

	def test_workflows_build_with_the_pinned_ndk(self):
		values = re.findall(r"^\s+NDK_VERSION: (.*)$", WORKFLOWS, re.M)
		self.assertTrue(values, "workflow NDK_VERSION")
		self.assertEqual(set(values), {ENV["ANDROID_NDK_VERSION"]}, "update the workflows with ANDROID_NDK_VERSION")

	def test_export_fixture_workflow_checks_its_sdk(self):
		fixture = (ROOT / "tools/test_android_export.py").read_text()
		self.assertIn("platforms/android-%s/android.jar" % re.search(r"compileSdk (\d+)", fixture).group(1), WORKFLOWS)
		self.assertIn("build-tools/%s/aapt2" % re.search(r"build-tools/([\w.]+)/aapt2", fixture).group(1), WORKFLOWS)

	def test_gdextension_minimum_is_the_built_api(self):
		for path in ["addons/firebase/godot_firebase.gdextension", "examples/crashlytics_smoke/crashlytics_smoke.gdextension.example"]:
			with self.subTest(path=path):
				descriptor = (ROOT / path).read_text()
				self.assertEqual(re.search(r'^compatibility_minimum = "(.*)"$', descriptor, re.M).group(1), ENV["GODOT_API_VERSION"])


if __name__ == "__main__":
	unittest.main()
