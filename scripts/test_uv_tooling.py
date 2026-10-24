"""Check locked uv routing without installing tools or running RTL simulation."""

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class UvMakeTests(unittest.TestCase):
    def dry_run(self, target, *options):
        result = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-n",
                target,
                "UV=uv-probe",
                "PYTHON=python-probe",
                *options,
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_setup_uses_locked_sync(self):
        self.assertIn('"uv-probe" sync --locked', self.dry_run("setup"))

    def test_style_and_format_select_locked_dev_group(self):
        for target in ("style", "format"):
            with self.subTest(target=target):
                self.assertIn(
                    '"uv-probe" run --locked --group dev "python-probe" scripts/check_style.py',
                    self.dry_run(target),
                )

    def test_tooling_tests_use_locked_python(self):
        self.assertIn(
            '"uv-probe" run --locked "python-probe" -m unittest discover',
            self.dry_run("test-tooling"),
        )

    def test_uv_failure_is_not_ignored_and_override_handles_spaces(self):
        with tempfile.TemporaryDirectory(prefix="uv executable ") as folder:
            executable = Path(folder) / "uv stub"
            executable.write_text("#!/bin/sh\nexit 7\n")
            executable.chmod(0o755)
            result = subprocess.run(
                ["make", "--no-print-directory", "style", f"UV={executable}"],
                cwd=ROOT,
                text=True,
                capture_output=True,
                timeout=10,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Error 7", result.stderr)

    def test_firmware_uses_locked_toolchain_and_preserves_zig_override(self):
        output = self.dry_run("firmware", "ZIG=/tmp/custom zig")
        self.assertEqual(output.count('run --locked --group toolchain "/tmp/custom zig"'), 2)
        self.assertIn('"python-zig" cc', self.dry_run("firmware"))

    def test_cmake_override_is_forwarded_in_locked_toolchain(self):
        self.assertIn(
            '--group toolchain "python-probe" scripts/build_llama.py --cmake "/tmp/custom cmake"',
            self.dry_run("llama", "CMAKE=/tmp/custom cmake"),
        )

    def test_toolchain_sync_is_explicit(self):
        self.assertIn('"uv-probe" sync --locked --group toolchain', self.dry_run("setup-toolchain"))
