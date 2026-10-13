#!/usr/bin/env python3
"""Check CPU-to-array arithmetic, command errors, reset and a corrupted golden result."""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build/matrix-regression")
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists():
        parser.error("Output directory already exists; choose --out to preserve earlier evidence")
    out.mkdir(parents=True)
    rows, negative = [], []
    for core in ("ibex", "cv32e40p"):
        base = [sys.executable, str(ROOT / "scripts/run_core.py"), core, "--probe", "matrix_probe"]
        for latency in (1, 2, 4, 8):
            for period in (1, 2, 3):
                run = out / core / f"latency{latency}-period{period}"
                result = subprocess.run(
                    [
                        *base,
                        "--latency",
                        str(latency),
                        "--grant-period",
                        str(period),
                        "--out",
                        str(run),
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode:
                    print(result.stdout + result.stderr, file=sys.stderr)
                    return result.returncode
                summary = json.loads((run / "summary.json").read_text())
                if not summary["passed"]:
                    raise RuntimeError(f"Matrix regression failed: {run}")
                rows.append(
                    {
                        "core": core,
                        "response_latency_cycles": latency,
                        "grant_period_cycles": period,
                        **summary["results"][0],
                    }
                )
        run = out / core / "corrupt-golden"
        result = subprocess.run(
            [*base, "--out", str(run)],
            env={**os.environ, "MATRIX_INJECT_FAILURE": "1"},
            capture_output=True,
            text=True,
            check=False,
        )
        summary = json.loads((run / "summary.json").read_text())
        detected = (
            result.returncode == summary["exit_code"] == 3
            and not summary["passed"]
            and "matrix result or RAM guard mismatch" in (run / "run.log").read_text()
        )
        negative.append(
            {
                "core": core,
                "case": "first golden matrix element deliberately incorrect",
                "runner_exit": result.returncode,
                "simulator_exit": summary["exit_code"],
                "detected": detected,
            }
        )
        if not detected:
            print(result.stdout + result.stderr, file=sys.stderr)
            raise RuntimeError("Corrupted golden result did not fail correctly")
    (out / "summary.json").write_text(
        json.dumps(
            {
                "scope": "Real INT8 array arithmetic; modeled RAM/MMIO with instantaneous tensor accesses",
                "simulator": "VCS Y-2026.03_Full64",
                "coverage": "Not measured",
                "runs": rows,
                "negative": negative,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"PASS matrix: {len(rows)} configurations and {len(negative)} deliberate failures; {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
