#!/usr/bin/env python3
"""The Linux desktop stub build replaces the library only with x86_64 code.

The Linux compiler gets no target flag, so a host compiler on arm64 Linux builds
arm64 code. Offline; a fake compiler writes only an ELF header.
"""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_desktop_stub", ROOT / "tools/build_desktop_stub.py")
STUB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STUB)
ELF64_LSB = b"\x7fELF\x02\x01" + bytes(12)
X86_64 = ELF64_LSB + b"\x3e\x00"
AARCH64 = ELF64_LSB + b"\xb7\x00"
LIBRARY = "libgodot_firebase.linux.x86_64.so"


class LinuxStubArchitectureTest(unittest.TestCase):
	def build(self, header):
		"""Run the Linux build with a compiler that writes header; return its exit code and bin/linux files."""
		with tempfile.TemporaryDirectory() as directory:
			root = Path(directory)
			linux = root / "addons/firebase/bin/linux"
			linux.mkdir(parents=True)
			(linux / LIBRARY).write_bytes(b"committed")

			def fake_compiler(command, check):
				Path(command[command.index("-o") + 1]).write_bytes(header)

			argv = ["build_desktop_stub.py", "--platform", "linux", "--arch", "x86_64", "--cc", "cc"]
			with mock.patch.object(STUB, "ROOT", root), mock.patch.object(STUB.subprocess, "run", fake_compiler), \
					mock.patch.object(sys, "argv", argv):
				try:
					STUB.main()
					status = 0
				except SystemExit as error:
					status = error.code
			return status, {path.name: path.read_bytes() for path in linux.iterdir()}

	def test_x86_64_output_replaces_the_library(self):
		self.assertEqual(self.build(X86_64), (0, {LIBRARY: X86_64}))

	def test_other_architecture_keeps_the_library(self):
		status, files = self.build(AARCH64)
		self.assertEqual(files, {LIBRARY: b"committed"})
		self.assertIn("did not build an x86_64 library", status)


if __name__ == "__main__":
	unittest.main()
