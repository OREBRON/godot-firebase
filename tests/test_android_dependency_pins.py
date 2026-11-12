#!/usr/bin/env python3
"""Android Maven pins match the versions the pinned Firebase C++ SDK expects.

The SDK's Android/firebase_dependencies.gradle names a Firebase BoM and a few
explicit artifacts; tools/bootstrap.sh fetches that BoM's POM at the SHA-256 in
tools/versions.env. Needs tools/bootstrap.sh output and skips without it.
"""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ElementTree

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(re.findall(r"^(\w+)=(.*)$", (ROOT / "tools/versions.env").read_text(), re.M))
SDK_GRADLE = ROOT / "third_party/firebase_cpp_sdk/Android/firebase_dependencies.gradle"
BOM = ROOT / "third_party" / ("firebase-bom-%s.pom" % ENV["FIREBASE_ANDROID_BOM_VERSION"])
EXPORT = (ROOT / "addons/firebase/export/firebase_android_gradle.gd").read_text()
BRIDGE = (ROOT / "android/build.gradle").read_text()
COORDINATE = r"([\w.-]+:[\w.-]+):(\d[\w.-]*)"
POM = {"m": "http://maven.apache.org/POM/4.0.0"}


@unittest.skipUnless(SDK_GRADLE.is_file(), "run tools/bootstrap.sh to download the pinned Firebase C++ SDK")
class AndroidDependencyPinsTest(unittest.TestCase):
	def test_sdk_names_the_pinned_bom(self):
		self.assertEqual(re.findall(r"firebase-bom:([\w.-]+)'", SDK_GRADLE.read_text()), [ENV["FIREBASE_ANDROID_BOM_VERSION"]],
			"update FIREBASE_ANDROID_BOM_VERSION/SHA256 in tools/versions.env, then the Maven pins")

	def test_maven_pins_match_the_bom_and_sdk(self):
		self.assertTrue(BOM.is_file(), "run tools/bootstrap.sh to download " + BOM.name)
		expected = {"%s:%s" % (d.findtext("m:groupId", namespaces=POM), d.findtext("m:artifactId", namespaces=POM)):
			d.findtext("m:version", namespaces=POM) for d in ElementTree.parse(BOM).iterfind(".//m:dependency", POM)}
		expected.update(re.findall(COORDINATE, SDK_GRADLE.read_text()))
		products = dict(re.findall(COORDINATE, re.search(r"const DEPENDENCIES := \{(.*?)\}", EXPORT, re.S).group(1)))
		self.assertTrue(products, "DEPENDENCIES of firebase_android_gradle.gd")
		for artifact, version in re.findall(COORDINATE, EXPORT + BRIDGE):
			if artifact in expected or artifact in products:
				with self.subTest(artifact=artifact):
					self.assertEqual(version, expected.get(artifact), "the C++ SDK expects " + BOM.name)


if __name__ == "__main__":
	unittest.main()
