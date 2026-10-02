#!/usr/bin/env python3
"""Fetch pinned upstream sources; optionally download the checksum-verified model."""

import argparse
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "dependencies.json").read_text())
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--model", action="store_true", help="Also download the approximately 1.28 GB model")
a = p.parse_args()


def run(*args):
    subprocess.run(args, check=True)


for name, spec in manifest["repositories"].items():
    dest = ROOT / ".deps" / name
    if not (dest / ".git").exists():
        dest.mkdir(parents=True, exist_ok=True)
        run("git", "init", str(dest))
        run("git", "-C", str(dest), "remote", "add", "origin", spec["url"])
        run("git", "-C", str(dest), "fetch", "--depth=1", "origin", spec["revision"])
        run("git", "-C", str(dest), "checkout", "--detach", spec["revision"])
    current = subprocess.check_output(
        ["git", "-C", str(dest), "rev-parse", "HEAD"], text=True
    ).strip()
    dirty = subprocess.check_output(
        ["git", "-C", str(dest), "status", "--porcelain"], text=True
    ).strip()
    if current != spec["revision"] or dirty:
        raise SystemExit(
            f"{name}: checkout differs from manifest; preserve local work and resolve before building"
        )
if a.model:
    spec = manifest["model"]
    dest = ROOT / ".deps" / "models" / spec["file"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        partial = dest.with_suffix(".partial")
        url = (
            f"https://huggingface.co/{spec['repository']}/resolve/{spec['revision']}/{spec['file']}"
        )
        run("curl", "-fL", "--retry", "2", url, "-o", str(partial))
    else:
        partial = dest
    with partial.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if actual != spec["sha256"]:
        raise SystemExit("Model SHA-256 mismatch; file is not usable")
    if partial != dest:
        partial.rename(dest)
print("Pinned dependencies verified")
