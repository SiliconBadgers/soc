#!/usr/bin/env python3
"""Check CPU-to-array arithmetic, command errors, reset and a corrupted golden result."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build/matrix-regression")
    parser.add_argument("--hls", action="store_true")
    parser.add_argument(
        "--resume", action="store_true", help="Reuse completed runs of the same binary and firmware"
    )
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists() and not args.resume:
        parser.error("Output directory already exists; choose --out to preserve earlier evidence")
    out.mkdir(parents=True, exist_ok=True)
    rows, negative = [], []
    for core in ("ibex", "cv32e40p"):
        base = [sys.executable, str(ROOT / "scripts/run_core.py"), core, "--probe", "matrix_probe"]
        if args.hls:
            base.append("--hls")
        build = ROOT / ("build/vcs-hls" if args.hls else "build/vcs") / core / "matrix_probe"
        binary = json.loads((build / "build.json").read_text())["binary_sha256"]
        if hashlib.sha256((build / "simv").read_bytes()).hexdigest() != binary:
            raise RuntimeError(f"Simulator differs from its build record: {build}")
        firmware = hashlib.sha256((ROOT / "build/firmware.bin").read_bytes()).hexdigest()
        for latency in (1, 2, 4, 8):
            for period in (1, 2, 3):
                run = out / core / f"latency{latency}-period{period}"
                reuse = args.resume and (run / "summary.json").is_file()
                if reuse:
                    summary = json.loads((run / "summary.json").read_text())
                    if not (
                        summary["passed"]
                        and summary["build"]["binary_sha256"] == binary
                        and summary["inputs"]["firmware"]["sha256"] == firmware
                        and summary["core"] == core
                        and summary["response_latency_cycles"] == latency
                        and summary["grant_period_cycles"] == period
                    ):
                        raise RuntimeError(f"Cannot reuse failed or changed evidence: {run}")
                elif run.exists():
                    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
                    run.rename(run.with_name(run.name + "-incomplete-" + stamp))
                if not reuse:
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
        if args.resume and (run / "summary.json").is_file():
            saved = json.loads((run / "summary.json").read_text())
            if (
                saved["build"]["binary_sha256"] != binary
                or saved["inputs"]["firmware"]["sha256"] != firmware
            ):
                raise RuntimeError(f"Cannot reuse changed negative-test evidence: {run}")
            runner_exit = saved["exit_code"]
        else:
            if run.exists():
                stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
                run.rename(run.with_name(run.name + "-incomplete-" + stamp))
            result = subprocess.run(
                [*base, "--out", str(run)],
                env={**os.environ, "MATRIX_INJECT_FAILURE": "1"},
                capture_output=True,
                text=True,
                check=False,
            )
            runner_exit = result.returncode
        summary = json.loads((run / "summary.json").read_text())
        detected = (
            runner_exit == summary["exit_code"] == 3
            and not summary["passed"]
            and "matrix result or RAM guard mismatch" in (run / "run.log").read_text()
        )
        negative.append(
            {
                "core": core,
                "case": "first golden matrix element deliberately incorrect",
                "runner_exit": runner_exit,
                "simulator_exit": summary["exit_code"],
                "detected": detected,
            }
        )
        if not detected:
            print((run / "run.log").read_text(), file=sys.stderr)
            raise RuntimeError("Corrupted golden result did not fail correctly")
    (out / "summary.json").write_text(
        json.dumps(
            {
                "scope": (
                    "INT8 array with HLS RAM/MMIO and arbitrated memory transactions"
                    if args.hls
                    else "Real INT8 array arithmetic; modeled RAM/MMIO with instantaneous tensor accesses"
                ),
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
