#!/usr/bin/env python3
"""iOS auth failures return FirebaseResult codes, never another error domain's,
and fail instead of waiting when no window can show the platform UI.

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

	def test_missing_presentation_window_fails_instead_of_waiting(self):
		# Presenting on nil shows nothing; GameKit then never calls back and Auth stays busy.
		guards = re.findall(r"UIViewController \*presenter = top_view_controller\(\);\s*if \(!presenter\) \{([^}]*)\}", SOURCE)
		self.assertEqual(len(guards), SOURCE.count("top_view_controller()"), "every presenter lookup is checked")
		for guard in guards:
			self.assertIn("failure(godot_firebase::kUnavailable, kNoPresentationWindow)", guard)
		self.assertTrue(any("finished = true;" in guard for guard in guards), "GameKit's later handler calls are ignored")


if __name__ == "__main__":
	unittest.main()
