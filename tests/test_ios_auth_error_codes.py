#!/usr/bin/env python3
"""iOS auth failures return FirebaseResult codes, never another error domain's.

Static check of src/auth/platform/platform_credentials_ios.mm: ASAuthorizationError,
GKError and FIRAuthErrorCode numbers are not firebase::auth::AuthError values, and
a failed Future may report error 0. Real platform errors still need a device.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/auth/platform/platform_credentials_ios.mm").read_text(encoding="utf-8")


class IosAuthErrorCodesTest(unittest.TestCase):
	def test_nserror_codes_are_only_compared(self):
		self.assertTrue("error.code ==" in SOURCE, "cancel checks compare NSError codes")
		self.assertEqual(re.findall(r"error\.code(?!\s*==)", SOURCE), [])

	def test_failed_future_never_reports_zero(self):
		guarded = "future.error() != 0 ? future.error() : godot_firebase::kUnavailable"
		self.assertTrue(guarded in SOURCE, "Game Center credential failure falls back to kUnavailable")
		self.assertIsNone(re.search(r"failure\(future\.error\(\),", SOURCE))


if __name__ == "__main__":
	unittest.main()
