#!/usr/bin/env python3
"""Sweep instruction/data response latency and grant cadence for the control probe."""

import argparse
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--output", default="build/control-sweep.json")
a = p.parse_args()
rows = []
for core in ["ibex", "cv32e40p"]:
    for latency in [1, 2, 4, 8]:
        for period in [1, 2, 3]:
            output = subprocess.check_output(
                [
                    str(ROOT / "build" / core / "core_probe"),
                    str(ROOT / "build/firmware.bin"),
                    str(latency),
                    str(period),
                ],
                text=True,
            )
            result = json.loads(output)
            if not result["pass"] or result["doorbells"] != 6 or result["completions"] != 6:
                raise SystemExit("Control probe failed")
            rows.append(
                {
                    "core": core,
                    "response_latency_cycles": latency,
                    "grant_period_cycles": period,
                    **result,
                }
            )
dest = ROOT / a.output
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(
    json.dumps(
        {
            "scope": "Control path only; no tensor traffic, DMA or accelerator performance model",
            "runs": rows,
        },
        indent=2,
    )
    + "\n"
)
print(f"{len(rows)} configurations passed; results: {a.output}")
