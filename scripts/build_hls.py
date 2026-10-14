#!/usr/bin/env python3
"""Generate the platform RAM/register RTL using pinned Bambu; do not simulate."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "PandA 2024.10 - Revision c2ba6936ca2ed63137095fea0b630a1c66e20e63-main"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bambu", default=os.environ.get("BAMBU", "bambu"))
    args = parser.parse_args()
    executable = shutil.which(args.bambu)
    if not executable:
        parser.error("Set BAMBU to the Bambu 2024.10 executable or Linux AppImage")
    version = subprocess.check_output([executable, "--version"], text=True, timeout=60)
    if VERSION not in version:
        parser.error(f"Required HLS compiler: {VERSION}")
    build = ROOT / "build/hls/platform"
    build.mkdir(parents=True, exist_ok=True)
    source = ROOT / "hls/platform_memory.cpp"
    shutil.copy2(source, build / source.name)
    command = [
        executable,
        source.name,
        "--top-fname=platform_memory",
        "--compiler=I386_CLANG16",
        "-O2",
        "--reset-level=low",
        "--registered-inputs=top",
        "--generate-interface=MINIMAL",
    ]
    with (build / "synthesis.log").open("w") as log:
        subprocess.run(
            command, cwd=build, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=900
        )
    rtl = build / "platform_memory.v"
    if not rtl.is_file() or "module platform_memory(" not in rtl.read_text():
        raise RuntimeError("HLS did not produce the required top module")
    files = [rtl, *sorted(build.glob("*.mem"))]
    record = {
        "compiler": VERSION,
        "source": str(source.relative_to(ROOT)),
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "arguments": command[1:],
        "outputs": [
            {"path": f.name, "sha256": hashlib.sha256(f.read_bytes()).hexdigest()} for f in files
        ],
        "rtl_simulation": "Not run by this command; use the VCS HLS integration checks",
        "physical_synthesis": "Not run",
    }
    (build / "manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"PASS HLS generation: {rtl}")


if __name__ == "__main__":
    main()
