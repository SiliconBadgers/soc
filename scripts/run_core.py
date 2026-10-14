#!/usr/bin/env python3
"""Run one VCS CPU/host probe and retain its JSON results and simulator log."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def input_record(path):
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"path": str(path), "sha256": digest}


def checked_results(text, probe, with_model, exit_code):
    """Reject incomplete output and simulator errors even if a probe prints PASS."""
    try:
        records = [json.loads(line) for line in text.splitlines() if line.startswith('{"')]
    except json.JSONDecodeError:
        return [], False
    failure = re.search(
        r"^\s*(?:Error(?:-|:)|Fatal(?:-|:))|assertion[^\n]*(?:fail|error)",
        text,
        re.MULTILINE | re.IGNORECASE,
    )
    expected = 2 if with_model and probe == "llama_probe" else 1
    passed = (
        exit_code == 0
        and failure is None
        and len(records) == expected
        and all(isinstance(r, dict) and r.get("pass") is True for r in records)
    )
    if passed and probe == "core_probe":
        passed = all(
            r.get("doorbells") == r.get("completions") == 6 and len(r.get("commands", [])) == 6
            for r in records
        )
    if passed and probe == "matrix_probe":
        passed = all(
            r.get("test") == "matrix_cpu_to_rtl"
            and r.get("valid_commands") == 8
            and r.get("rejected_commands") == 15
            and r.get("checked_elements") == 401
            and r.get("active_resets") == 1
            and r.get("completion_stall_cycles", 0) > 0
            and r.get("command_cycles", 0) > 0
            for r in records
        )
    if passed and probe == "workload_probe":
        passed = all(
            r.get("test") == "qwen_partial_int8_hardware"
            and r.get("hardware_stages") == 2
            and r.get("hardware_commands", 0) > 0
            and r.get("checked_integer_outputs", 0) > 0
            and r.get("replaced_projection_values", 0) > 0
            and r.get("compared_logits", 0) > 0
            and r.get("max_abs_logit_error", 1) <= 1e-5
            and r.get("original_model_logit_delta", 0) > 0
            for r in records
        )
    return records, passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("core", choices=["ibex", "cv32e40p"])
    parser.add_argument("--hls", action="store_true")
    parser.add_argument(
        "--probe",
        choices=["core_probe", "llama_probe", "matrix_probe", "workload_probe"],
        default="core_probe",
    )
    parser.add_argument("--firmware", type=Path, default=ROOT / "build/firmware.bin")
    parser.add_argument("--model", type=Path)
    parser.add_argument("--latency", type=int, default=1)
    parser.add_argument("--grant-period", type=int, default=1)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    build = ROOT / ("build/vcs-hls" if args.hls else "build/vcs") / args.core / args.probe
    out = (args.out or build / "run").resolve()
    out.mkdir(parents=True, exist_ok=True)
    firmware = args.firmware.resolve()
    if not firmware.is_file() or args.latency < 1 or args.grant_period < 1:
        parser.error("Provide a firmware binary and positive memory latency/grant period")
    if args.model and (
        args.probe not in ("llama_probe", "workload_probe") or not args.model.is_file()
    ):
        parser.error("--model requires an existing model and a llama/workload probe")
    if args.probe == "workload_probe" and (not args.model or not args.hls):
        parser.error("workload_probe requires --hls and --model")
    helper = ROOT / "components/rtl/scripts/vcs.py"
    if (
        not helper.is_file()
        or not (build / "simv").is_file()
        or not (build / "build.json").is_file()
    ):
        parser.error(
            "Missing shared VCS helper or compiled probe; initialize components and build first"
        )
    metadata = json.loads((build / "build.json").read_text())
    if metadata["binary_sha256"] != hashlib.sha256((build / "simv").read_bytes()).hexdigest():
        parser.error("Simulator binary differs from its build record; rebuild the probe")
    if args.hls:
        if metadata.get("platform") != "HLS RTL":
            parser.error("The requested probe was not built with HLS RTL")
        for record in metadata["hls"]["outputs"]:
            if record["path"].endswith(".mem"):
                memory = build / record["path"]
                if (
                    not memory.is_file()
                    or hashlib.sha256(memory.read_bytes()).hexdigest() != record["sha256"]
                ):
                    parser.error(f"HLS initialization file changed: {memory}; rebuild the probe")
    inputs = {"firmware": input_record(firmware)}
    if args.model:
        inputs["model"] = input_record(args.model.resolve())
    command = [
        sys.executable,
        str(helper),
        "--elapsed-file",
        str(out / "run.elapsed"),
        "run",
        str(build / "simv"),
        f"+firmware={firmware}",
        f"+latency={args.latency}",
        f"+grant_period={args.grant_period}",
    ]
    if args.model:
        command.append(f"+model={args.model.resolve()}")
    with (out / "run.log").open("w") as log:
        result = subprocess.run(
            command, cwd=build, stdout=log, stderr=subprocess.STDOUT, check=False
        )
    text = (out / "run.log").read_text()
    records, passed = checked_results(text, args.probe, bool(args.model), result.returncode)
    summary = {
        "build": metadata,
        "core": args.core,
        "probe": args.probe,
        "inputs": inputs,
        "response_latency_cycles": args.latency,
        "grant_period_cycles": args.grant_period,
        "seed": "Not applicable: deterministic inputs",
        "passed": passed,
        "exit_code": result.returncode,
        "results": records,
        "elapsed_seconds": float((out / "run.elapsed").read_text()),
        "coverage": "Not measured",
        "log": str(out / "run.log"),
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary))
    if not passed:
        print(text, file=sys.stderr)
        return result.returncode or 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
