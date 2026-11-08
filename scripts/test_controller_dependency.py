"""Reject controller dependency drift before launching the licensed regression."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from controller_tests import controller_dependency


class ControllerDependencyTests(unittest.TestCase):
    def test_locked_checkout_and_development_override(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            subprocess.run(["git", "init", "-q", str(directory)], check=True)
            source = directory / "source.sv"
            source.write_text("module fixture; endmodule\n")
            subprocess.run(["git", "-C", str(directory), "add", "source.sv"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(directory),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                check=True,
            )
            revision = subprocess.check_output(
                ["git", "-C", str(directory), "rev-parse", "HEAD"], text=True
            ).strip()
            self.assertEqual(controller_dependency(directory, revision), (revision, False))
            with self.assertRaisesRegex(ValueError, "expected"):
                controller_dependency(directory, "0" * 40)
            source.write_text(source.read_text() + "// edited\n")
            with self.assertRaisesRegex(ValueError, "local changes"):
                controller_dependency(directory, revision)
            self.assertEqual(controller_dependency(directory), (revision, True))
            subprocess.run(["git", "-C", str(directory), "checkout", "--", "source.sv"], check=True)
            (directory / "untracked.sv").touch()
            with self.assertRaisesRegex(ValueError, "local changes"):
                controller_dependency(directory, revision)

    def test_missing_checkout_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "make deps"):
                controller_dependency(Path(temporary), "0" * 40)


if __name__ == "__main__":
    unittest.main()
