#!/usr/bin/env python3
"""Compile and run the independent command-router testbench with VCS."""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/router/vcs"
BUILD.mkdir(parents=True, exist_ok=True)
HELPER = ROOT / "components/rtl/scripts/vcs.py"
SOURCES = [
    "components/rtl/rtl/common/command_pkg.sv",
    "sim/engine_stub.sv",
    "components/rtl/rtl/control/command_router.sv",
    "sim/command_router_test_top.sv",
    "components/verification/tb/command_router_tb.sv",
]
for name, args in [
    (
        "compile",
        [
            "compile",
            "-top",
            "command_router_tb",
            *SOURCES,
            f"-Mdir={BUILD / 'csrc'}",
            "-o",
            str(BUILD / "simv"),
        ],
    ),
    ("run", ["run", str(BUILD / "simv")]),
]:
    log = BUILD / f"{name}.log"
    with log.open("w") as stream:
        result = subprocess.run(
            [sys.executable, str(HELPER), "--elapsed-file", str(BUILD / f"{name}.elapsed"), *args],
            cwd=ROOT,
            stdout=stream,
            stderr=subprocess.STDOUT,
            check=False,
        )
    print(log.read_text(), end="")
    if result.returncode:
        raise SystemExit(result.returncode)
if "PASS router: 8 commands" not in log.read_text():
    raise SystemExit("FAIL: missing command-router completion result")
