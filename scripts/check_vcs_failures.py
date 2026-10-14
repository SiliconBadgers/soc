#!/usr/bin/env python3
"""Verify that invalid firmware and an unknown DPI output produce failing VCS exits."""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
os.chdir(root)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, default=root / "build/vcs-negative")
parser.add_argument("--hls", action="store_true")
args = parser.parse_args()
flags = ["--hls"] if args.hls else []
negative = args.out.resolve()
if negative.exists():
    parser.error("Output directory already exists; use --out to preserve earlier evidence")
negative.mkdir(parents=True)
empty = negative / "empty-firmware.bin"
empty.write_bytes(b"")
rows = []
for core in ("ibex", "cv32e40p"):
    out = negative / ("empty-firmware-" + core)
    result = subprocess.run(
        [
            sys.executable,
            "scripts/run_core.py",
            core,
            *flags,
            "--firmware",
            str(empty),
            "--out",
            str(out),
        ],
        capture_output=True,
        text=True,
    )
    summary = json.loads((out / "summary.json").read_text())
    log = (out / "run.log").read_text()
    detected = (
        result.returncode == 3
        and summary["exit_code"] == 3
        and not summary["passed"]
        and "firmware overlaps mailbox" in log
    )
    rows.append(
        {
            "case": "empty firmware",
            "core": core,
            "runner_exit": result.returncode,
            "simulator_exit": summary["exit_code"],
            "detected": detected,
        }
    )
    if not detected:
        print(log)
        raise SystemExit("Empty firmware was not rejected correctly")

scratch = negative / "unknown-output"
(scratch / "scripts").mkdir(parents=True, exist_ok=True)
shutil.copytree(root / "sim", scratch / "sim", dirs_exist_ok=True)
for directory in ("components", ".deps", "rtl"):
    (scratch / directory).symlink_to(root / directory, target_is_directory=True)
if args.hls:
    (scratch / "hls").symlink_to(root / "hls", target_is_directory=True)
    (scratch / "build").mkdir()
    (scratch / "build/hls").symlink_to(root / "build/hls", target_is_directory=True)
for script in ("build_core.py", "run_core.py"):
    shutil.copy2(root / "scripts" / script, scratch / "scripts" / script)
sv = scratch / ("sim/hls_platform_vcs_tb.sv" if args.hls else "sim/control_path_vcs_tb.sv")
text = sv.read_text()
needle = "    outputs[0+:1] = host_gnt_o;" if args.hls else "    outputs[352+:1] = idle_o;"
assert text.count(needle) == 1
injection = "\n    outputs[0+:1] = 1'bx;" if args.hls else "\n    outputs[224+:1] = 1'bx;"
sv.write_text(text.replace(needle, needle + injection))
with (negative / "unknown-compile.log").open("w") as log:
    subprocess.run(
        [sys.executable, str(scratch / "scripts/build_core.py"), "ibex", *flags],
        cwd=scratch,
        stdout=log,
        stderr=subprocess.STDOUT,
        check=True,
    )
out = scratch / "run"
result = subprocess.run(
    [
        sys.executable,
        str(scratch / "scripts/run_core.py"),
        "ibex",
        *flags,
        "--firmware",
        str(root / "build/firmware.bin"),
        "--out",
        str(out),
    ],
    cwd=scratch,
    capture_output=True,
    text=True,
)
summary = json.loads((out / "summary.json").read_text())
log = (out / "run.log").read_text()
detected = (
    result.returncode == 3
    and summary["exit_code"] == 3
    and not summary["passed"]
    and ("Unknown HLS RTL output: host_gnt_o" if args.hls else "Unknown RTL output: cmd_ready_o")
    in log
)
rows.append(
    {
        "case": "DPI host_gnt_o forced to X" if args.hls else "DPI cmd_ready_o forced to X",
        "core": "ibex",
        "runner_exit": result.returncode,
        "simulator_exit": summary["exit_code"],
        "detected": detected,
    }
)
(negative / "summary.json").write_text(json.dumps(rows, indent=2) + "\n")
print(json.dumps(rows, indent=2))
if not detected:
    print(log)
    raise SystemExit("Unknown output was not rejected correctly")
