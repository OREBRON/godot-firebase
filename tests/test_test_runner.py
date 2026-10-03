"""The stock runner must reject import failures even when Godot exits with zero."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get("GODOT") or shutil.which("godot"), "Godot required")
class RunnerImportTests(unittest.TestCase):
    def test_broken_extension_cannot_be_hidden_by_successful_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / "tools").mkdir()
            (project / "tests").mkdir()
            shutil.copy2(ROOT / "tools/run_tests.py", project / "tools/run_tests.py")
            (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Runner regression"\n')
            (project / "broken.bin").write_bytes(b"invalid native library")
            (project / "broken.gdextension").write_text('''[configuration]
entry_symbol = "godot_firebase_library_init"
compatibility_minimum = "4.7"
[libraries]
macos = "res://broken.bin"
linux = "res://broken.bin"
windows = "res://broken.bin"
''')
            (project / "tests/test_success.gd").write_text('''extends SceneTree
func _initialize() -> void:
    print("test_success.gd: ok")
    quit(0)
''')
            result = subprocess.run([sys.executable, str(project / "tools/run_tests.py")],
                                    capture_output=True, text=True, timeout=90)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("import", (result.stdout + result.stderr).lower())


if __name__ == "__main__":
    unittest.main()
