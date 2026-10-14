#!/usr/bin/env python3
"""Run partial Qwen hardware co-execution and prove an incorrect oracle is rejected."""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=ROOT / ".deps/models/Qwen3.5-2B-Q4_K_M.gguf")
    parser.add_argument("--out", type=Path, default=ROOT / "build/hls-workload-regression")
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists():
        parser.error("Choose a new --out directory to preserve earlier evidence")
    out.mkdir(parents=True)
    cases = []
    for core in ("ibex", "cv32e40p"):
        for corrupt in (False, True):
            destination = out / core / ("corrupt" if corrupt else "reference")
            command = [
                sys.executable,
                str(ROOT / "scripts/run_core.py"),
                core,
                "--hls",
                "--probe",
                "workload_probe",
                "--model",
                str(args.model.resolve()),
                "--out",
                str(destination),
            ]
            env = dict(os.environ)
            env.pop("WORKLOAD_INJECT_FAILURE", None)
            if corrupt:
                env["WORKLOAD_INJECT_FAILURE"] = "1"
            result = subprocess.run(command, env=env, capture_output=True, text=True, check=False)
            summary = json.loads((destination / "summary.json").read_text())
            detected = (
                (
                    result.returncode == summary["exit_code"] == 3
                    and not summary["passed"]
                    and "real-workload RTL arithmetic mismatch"
                    in (destination / "run.log").read_text()
                )
                if corrupt
                else result.returncode == 0 and summary["passed"]
            )
            cases.append(
                {
                    "core": core,
                    "corrupt_oracle": corrupt,
                    "exit_code": result.returncode,
                    "passed": detected,
                    "results": summary["results"],
                }
            )
            if not detected:
                raise RuntimeError(result.stdout + result.stderr)
    (out / "summary.json").write_text(
        json.dumps({"cases": cases, "coverage": "Not measured"}, indent=2) + "\n"
    )
    print("PASS partial Qwen co-execution: both cores and both deliberately incorrect oracles")


if __name__ == "__main__":
    main()
