#!/usr/bin/env python3
"""Build an unmodified upstream CPU plus the integration boundary using Verilator."""

import argparse
import os
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument("core", choices=["ibex", "cv32e40p"])
p.add_argument("--source", default="sim/core_probe.cpp")
p.add_argument("--output", default="core_probe")
p.add_argument("--link-ggml", action="store_true")
p.add_argument(
    "--lint-only",
    action="store_true",
    help="Elaborate both project and vendor RTL without building C++",
)
a = p.parse_args()
os.chdir(ROOT)
files = [
    "components/architecture/contracts/integration/command_pkg.sv",
    "rtl/integration/engine_stub.sv",
    "components/rtl-control/rtl/integration/command_router.sv",
    "rtl/integration/command_router_test_top.sv",
    "rtl/integration/riscv_wrapper.sv",
    "sim/control_path_sim_top.sv",
]
opts = []
if a.core == "cv32e40p":
    rtl = ".deps/cv32e40p/rtl"
    opts += ["-DUSE_CV32E40P", f"-I{rtl}/include", "-I.deps/cv32e40p/bhv/include"]
    sources = []
    for line in pathlib.Path(".deps/cv32e40p/cv32e40p_manifest.flist").read_text().splitlines():
        if line.startswith("${DESIGN_RTL_DIR}") and "tb_wrapper" not in line:
            sources.append(line.replace("${DESIGN_RTL_DIR}", rtl))
else:
    rtl = ".deps/ibex/rtl"
    prim = ".deps/ibex/vendor/lowrisc_ip/ip/prim/rtl"
    opts += [f"-I{prim}", "-I.deps/ibex/vendor/lowrisc_ip/dv/sv/dv_utils"]
    sources = [
        f"{prim}/prim_cipher_pkg.sv",
        f"{prim}/prim_util_pkg.sv",
        f"{prim}/prim_secded_pkg.sv",
        f"{rtl}/ibex_pkg.sv",
        f"{rtl}/ibex_cheriot_pkg.sv",
    ]
    sources += [
        str(x)
        for x in sorted(pathlib.Path(rtl).glob("*.sv"))
        if x.name
        not in [
            "ibex_pkg.sv",
            "ibex_cheriot_pkg.sv",
            "ibex_top.sv",
            "ibex_lockstep.sv",
            "ibex_tracer.sv",
            "ibex_top_tracing.sv",
            "ibex_trvk.sv",
            "ibex_register_file_fpga.sv",
            "ibex_register_file_latch.sv",
        ]
    ]
    sources += [f"{prim}/prim_lfsr.sv"]
    # SecureIbex=0 removes prim_buf; ICache=0 removes RAM primitive integration.
build = ROOT / "build" / a.core
build.mkdir(parents=True, exist_ok=True)
cflags = f"-std=c++17 -I{ROOT / 'sim'}"
lflags = ""
if a.link_ggml:
    cflags += f" -I{ROOT}/.deps/llama.cpp/ggml/include -I{ROOT}/.deps/llama.cpp/include"
    lib = ROOT / "build/llama/bin"
    lflags = f"-L{lib} -Wl,-rpath,{lib} -lllama -lggml -lggml-base -lggml-cpu"
cmd = [
    "verilator",
    "--cc",
    "--exe",
    "--build",
    "-j",
    "4",
    "--assert",
    "--top-module",
    "control_path_sim_top",
    "--Mdir",
    str(build),
    "config/vendor.vlt",
    "-CFLAGS",
    cflags,
    "-o",
    a.output,
    *opts,
    *sources,
    *files,
    str(ROOT / a.source),
]
if lflags:
    cmd += ["-LDFLAGS", lflags]
if a.lint_only:
    start = cmd.index("--cc")
    end = cmd.index("--assert")
    cmd[start:end] = ["--lint-only"]
    cmd.remove(str(ROOT / a.source))
subprocess.run(cmd, check=True)
