#!/usr/bin/env python3
"""Build host libraries with the same compiler environment used by the VCS DPI probe."""

import argparse
import importlib.util
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cmake", default="cmake")
args = parser.parse_args()
helper = ROOT / "components/rtl/scripts/vcs.py"
spec = importlib.util.spec_from_file_location("vcs_tooling", helper)
if spec is None or spec.loader is None:
    parser.error("Initialize the pinned RTL component first")
vcs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vcs)
prefix = vcs.launcher()
print(vcs.check_version(prefix), flush=True)
compiler_version = subprocess.check_output(
    [*prefix, "g++", "-dumpfullversion", "-dumpversion"], text=True, timeout=30
).strip()
# GCC 8 supplies C++17 filesystem in a separate library.
standard_libraries = "-lstdc++fs" if int(compiler_version.split(".")[0]) < 9 else ""
print(f"Building llama.cpp with GCC {compiler_version}", flush=True)
compilers = ROOT / "build/vcs-compilers"
compilers.mkdir(parents=True, exist_ok=True)
for name, executable in [("cc", "gcc"), ("cxx", "g++")]:
    wrapper = compilers / name
    wrapper.write_text("#!/bin/sh\nexec " + shlex.join([*prefix, executable]) + ' "$@"\n')
    wrapper.chmod(0o755)
subprocess.run(
    [
        args.cmake,
        "-S",
        str(ROOT / ".deps/llama.cpp"),
        "-B",
        str(ROOT / "build/llama"),
        "-DCMAKE_C_COMPILER=" + str(compilers / "cc"),
        "-DCMAKE_CXX_COMPILER=" + str(compilers / "cxx"),
        # Host CMake may detect a newer linker than the compiler container uses.
        "-DCMAKE_LINK_DEPENDS_USE_LINKER=OFF",
        "-DCMAKE_CXX_STANDARD_LIBRARIES=" + standard_libraries,
        "-DLLAMA_BUILD_TESTS=OFF",
        "-DLLAMA_BUILD_EXAMPLES=OFF",
        "-DLLAMA_BUILD_TOOLS=OFF",
        "-DLLAMA_BUILD_SERVER=OFF",
        "-DGGML_METAL=OFF",
        "-DGGML_BLAS=OFF",
        "-DGGML_OPENMP=OFF",
        "-DGGML_NATIVE=OFF",
    ],
    cwd=ROOT,
    check=True,
    timeout=900,
)
subprocess.run(
    [
        args.cmake,
        "--build",
        str(ROOT / "build/llama"),
        "--target",
        "llama",
        "ggml",
        "-j4",
    ],
    cwd=ROOT,
    check=True,
    timeout=1800,
)
