#!/usr/bin/env python3
"""Check CSR regeneration, stale-output rejection, and software layout."""

import importlib.metadata
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts/generate_controller_regs.py"


class ControllerGenerationTests(unittest.TestCase):
    def run_generator(self, output, *arguments, success=True):
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--out", str(output), *arguments],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_configuration_and_software_layout(self):
        compiler = shutil.which("cc")
        self.assertIsNotNone(compiler, "A C compiler is required for the generated header check")
        for payload, counter in ((32, 2), (128, 4), (512, 32), (1792, 32)):
            with (
                self.subTest(payload=payload, counter=counter),
                tempfile.TemporaryDirectory() as temp,
            ):
                output = Path(temp)
                arguments = ("--payload-width", str(payload), "--counter-width", str(counter))
                self.run_generator(output, *arguments)
                self.run_generator(output, *arguments, "--check")
                source = output / "layout.c"
                source.write_text(
                    '#include "controller_regs.h"\n'
                    '#include "controller_host.h"\n#include "controller_firmware.h"\n'
                    "#include <stddef.h>\n"
                    '_Static_assert(offsetof(controller_host_t, control) == 4, "control");\n'
                    '_Static_assert(offsetof(controller_firmware_t, wait_target) == 0x30, "wait");\n'
                    '_Static_assert(offsetof(controller_host_t, queue[1]) == 0x200, "matrix");\n'
                    '_Static_assert(offsetof(controller_firmware_t, queue[2].payload) == 0x320, "vector");\n'
                    f'_Static_assert(sizeof(((controller_firmware_t *)0)->queue[0].payload) == {payload // 8}, "payload");\n'
                    f'_Static_assert(CONTROLLER_COUNTER_WIDTH == {counter}, "counter");\n'
                )
                subprocess.run(
                    [compiler, "-std=gnu11", "-Wall", "-Werror", "-fsyntax-only", str(source)],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )

    def test_freestanding_word_accesses(self):
        pins = json.loads((ROOT / "dependencies.json").read_text())["tools"]
        self.assertEqual(importlib.metadata.version("ziglang"), pins["ziglang"])
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            self.run_generator(output, "--payload-width", "512", "--counter-width", "32")
            source = output / "access.c"
            source.write_text(
                '#include "controller_regs.h"\n'
                "__attribute__((noinline)) void result_write(uintptr_t base, uint32_t value) {\n"
                "  controller_write32(base, CONTROLLER_RESULT_OFFSET, value);\n}\n"
                "__attribute__((noinline)) uint32_t wait_read(uintptr_t base) {\n"
                "  return controller_read32(base, CONTROLLER_WAIT_STATUS_OFFSET);\n}\n"
                "__attribute__((noinline)) void queue_write(uintptr_t base, uint32_t value) {\n"
                "  controller_write32(base, CONTROLLER_QUEUE_2_PAYLOAD_15_OFFSET, value);\n}\n"
                "__attribute__((noinline)) uint32_t queue_read(uintptr_t base) {\n"
                "  return controller_read32(base, CONTROLLER_QUEUE_1_PAYLOAD_0_OFFSET);\n}\n"
            )
            assembly = output / "access.s"
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "ziglang",
                    "cc",
                    "-target",
                    "riscv32-freestanding",
                    "-mcpu=generic_rv32+m",
                    "-ffreestanding",
                    "-fomit-frame-pointer",
                    "-fno-stack-protector",
                    "-O2",
                    "-g0",
                    "-S",
                    str(source),
                    "-o",
                    str(assembly),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=30,
            )
            text = assembly.read_text()
            for name, operation in (
                ("result_write", "sw"),
                ("wait_read", "lw"),
                ("queue_write", "sw"),
                ("queue_read", "lw"),
            ):
                with self.subTest(helper=name):
                    body = text.split(f"{name}:", 1)[1].split(".Lfunc_end", 1)[0]
                    memory_operations = re.findall(r"^\s*(lb|lbu|lh|lhu|sb|sh|lw|sw)\s", body, re.M)
                    self.assertEqual(memory_operations, [operation], body)

    def test_stale_and_missing_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "generated"
            self.run_generator(output, "--check", success=False)
            self.run_generator(output)
            path = output / "controller_host.sv"
            path.write_text(path.read_text() + "// changed\n")
            self.run_generator(output, "--check", success=False)
            self.run_generator(output)
            self.run_generator(output, "--counter-width", "32", "--check", success=False)

    def test_invalid_widths(self):
        with tempfile.TemporaryDirectory() as temp:
            for option, value in (
                ("--payload-width", "0"),
                ("--payload-width", "33"),
                ("--payload-width", "1824"),
                ("--counter-width", "1"),
                ("--counter-width", "33"),
            ):
                with self.subTest(option=option, value=value):
                    self.run_generator(Path(temp), option, value, success=False)


if __name__ == "__main__":
    unittest.main()
