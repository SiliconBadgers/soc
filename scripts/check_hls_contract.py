#!/usr/bin/env python3
"""Check C++ contract vectors against generated RTL using VCS, including a bad oracle."""

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    build = ROOT / "build/hls-contract"
    build.mkdir(parents=True, exist_ok=True)
    generated = ROOT / "build/hls/platform"
    manifest = json.loads((generated / "manifest.json").read_text())
    if (
        manifest["source_sha256"]
        != hashlib.sha256((ROOT / manifest["source"]).read_bytes()).hexdigest()
    ):
        raise RuntimeError("HLS source differs from the generated RTL")
    for record in manifest["outputs"]:
        source = generated / record["path"]
        if hashlib.sha256(source.read_bytes()).hexdigest() != record["sha256"]:
            raise RuntimeError(f"HLS output differs from manifest: {source}")
        if source.suffix == ".mem":
            shutil.copy2(source, build / source.name)
    subprocess.run(
        [
            "c++",
            "-std=c++17",
            "-O2",
            "-Wall",
            "-Wextra",
            "-Werror",
            str(ROOT / "hls/platform_memory.cpp"),
            str(ROOT / "hls/platform_memory_test.cpp"),
            "-o",
            str(build / "contract"),
        ],
        check=True,
        timeout=60,
    )
    vectors = build / "vectors.txt"
    subprocess.run([str(build / "contract"), str(vectors)], check=True, timeout=60)
    helper = [sys.executable, str(ROOT / "components/rtl/scripts/vcs.py")]
    with (build / "compile.log").open("w") as log:
        subprocess.run(
            [
                *helper,
                "compile",
                "-top",
                "platform_memory_tb",
                str(generated / "platform_memory.v"),
                str(ROOT / "tb/platform_memory_tb.sv"),
                "-Mdir=" + str(build / "csrc"),
                "-o",
                str(build / "simv"),
            ],
            cwd=build,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=True,
        )
    cases = []
    for corrupt in (False, True):
        path = build / ("corrupt.log" if corrupt else "run.log")
        command = [*helper, "run", str(build / "simv"), f"+vectors={vectors}"]
        if corrupt:
            command.append("+corrupt=1")
        with path.open("w") as log:
            result = subprocess.run(
                command, cwd=build, stdout=log, stderr=subprocess.STDOUT, check=False
            )
        text = path.read_text()
        passed = (
            (result.returncode == 3 and "HLS contract mismatch" in text)
            if corrupt
            else (
                result.returncode == 0
                and '"checks":16485,"pass":true' in text
                and "Error" not in text
            )
        )
        cases.append({"corrupt_oracle": corrupt, "exit_code": result.returncode, "passed": passed})
        if not passed:
            raise RuntimeError(text)
    summary = {
        "compiler": manifest["compiler"],
        "cases": cases,
        "checks": 16485,
        "vectors_sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
        "coverage": "Not measured",
        "hls": manifest,
    }
    (build / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("PASS HLS contract: 16485 VCS checks and one deliberately incorrect oracle")


if __name__ == "__main__":
    main()
