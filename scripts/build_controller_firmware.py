#!/usr/bin/env python3
"""Build the freestanding controller C fixture with the locked Zig compiler."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--zig", default="python-zig")
    args = parser.parse_args()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    generated = args.generated.resolve()
    version = subprocess.check_output([args.zig, "version"], text=True, timeout=30).strip()
    expected = json.loads((ROOT / "dependencies.json").read_text())["tools"]["ziglang"]
    if version != expected:
        parser.error(f"Zig {version} differs from pinned {expected}")
    sources = [
        ROOT / "firmware/controller" / name for name in ("csr_backpressure.c", "start.S", "link.ld")
    ]
    elf = output / "firmware.elf"
    binary = output / "firmware.bin"
    commands = [
        [
            args.zig,
            "cc",
            "-target",
            "riscv32-freestanding",
            "-mcpu=generic_rv32+m",
            "-mabi=ilp32",
            "-mno-relax",
            "-msmall-data-limit=0",
            "-nostdlib",
            "-ffreestanding",
            "-fno-stack-protector",
            "-fno-unwind-tables",
            "-fno-asynchronous-unwind-tables",
            "-O2",
            "-g",
            "-Wall",
            "-Wextra",
            "-Werror",
            f"-Wl,-T,{sources[2]}",
            f"-I{generated}",
            str(sources[1]),
            str(sources[0]),
            "-o",
            str(elf),
        ],
        [args.zig, "objcopy", "-O", "binary", str(elf), str(binary)],
    ]
    for command in commands:
        subprocess.run(command, check=True, timeout=180)
    image = binary.read_bytes()
    image += bytes((-len(image)) % 4)
    image += bytes.fromhex("13000000") * 8
    if 128 + len(image) > 16384:
        parser.error("Firmware image and prefetch padding exceed the 16 KiB local RAM")
    words = [
        int.from_bytes(image[index : index + 4], "little") for index in range(0, len(image), 4)
    ]
    (output / "firmware.hex").write_text("".join(f"{word:08x}\n" for word in words))
    disassembler = shutil.which("llvm-objdump")
    if not disassembler:
        parser.error("llvm-objdump is required to retain the firmware disassembly")
    disassembly = subprocess.check_output(
        [disassembler, "--disassemble", str(elf)], text=True, timeout=30
    )
    (output / "firmware.dis").write_text(disassembly)
    manifest = {
        "schema": 1,
        "compiler": f"Zig {version}",
        "disassembler": subprocess.check_output(
            [disassembler, "--version"], text=True, timeout=30
        ).splitlines()[:3],
        "commands": commands,
        "sources": {
            str(path.relative_to(ROOT)): digest(path)
            for path in [*sources, Path(__file__).resolve()]
        },
        "generated_manifest_sha256": digest(generated / "manifest.json"),
        "entry_address": 128,
        "hex_words": len(words),
        "outputs": {
            path.name: digest(path)
            for path in (elf, binary, output / "firmware.hex", output / "firmware.dis")
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {len(image)} loaded bytes with Zig {version}: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
