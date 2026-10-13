#!/usr/bin/env python3
"""Build the CPU integration probe with VCS; use Verilator only for lint."""

import argparse
import hashlib
import json
import os
import pathlib
import shlex
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
    "components/rtl/rtl/common/command_pkg.sv",
    "sim/engine_stub.sv",
    "components/rtl/rtl/control/command_router.sv",
    "sim/command_router_test_top.sv",
    "rtl/riscv_wrapper.sv",
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
build = ROOT / "build/vcs" / a.core / a.output
build.mkdir(parents=True, exist_ok=True)
if a.lint_only:
    subprocess.run(
        [
            "verilator",
            "--lint-only",
            "--assert",
            "--top-module",
            "control_path_sim_top",
            "config/vendor.vlt",
            *opts,
            *sources,
            *files,
        ],
        check=True,
        timeout=900,
    )
else:
    import sys

    helper = ROOT / "components/rtl/scripts/vcs.py"
    if not helper.is_file():
        p.error("Pinned RTL component lacks scripts/vcs.py; initialize the VCS-enabled revision")
    subprocess.run([sys.executable, str(helper), "check"], check=True)
    source = (ROOT / a.source).resolve()
    if not source.is_file():
        p.error(f"Probe source missing: {source}")
    entry = build / "probe.cpp"
    entry.write_text(
        "#define main host_probe_main\n"
        f'#include "{source}"\n'
        "#undef main\n"
        f"constexpr bool ProbeUsesModel = {str(a.link_ggml).lower()};\n"
        '#include "probe_entry.hpp"\n'
    )
    cflags = ["-std=c++17", "-I" + str(ROOT / "sim")]
    extra = []
    if a.link_ggml:
        cflags += [
            "-I" + str(ROOT / ".deps/llama.cpp/ggml/include"),
            "-I" + str(ROOT / ".deps/llama.cpp/include"),
        ]
        lib = ROOT / "build/llama/bin"
        extra = [
            "-LDFLAGS",
            shlex.join(
                [f"-L{lib}", f"-Wl,-rpath,{lib}", "-lllama", "-lggml", "-lggml-base", "-lggml-cpu"]
            ),
        ]
    vcs_opts = ["+incdir+" + x[2:] if x.startswith("-I") else "+define+" + x[2:] for x in opts]
    command = [
        sys.executable,
        str(helper),
        "--elapsed-file",
        str(build / "compile.elapsed"),
        "compile",
        "-top",
        "control_path_vcs_tb",
        *vcs_opts,
        *sources,
        *files,
        "sim/control_path_vcs_tb.sv",
        str(entry),
        "-CFLAGS",
        shlex.join(cflags),
        *extra,
        "-Mdir=" + str(build / "csrc"),
        "-o",
        str(build / "simv"),
    ]
    with (build / "compile.log").open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        print((build / "compile.log").read_text(), file=sys.stderr)
        raise SystemExit(result.returncode)
    inputs = [
        *(ROOT / name for name in sources + files),
        source,
        ROOT / "sim/control_path_vcs_tb.sv",
        ROOT / "sim/sim_host.hpp",
        ROOT / "sim/sim_signals.hpp",
        ROOT / "sim/probe_entry.hpp",
    ]
    metadata = {
        "simulator": "VCS Y-2026.03_Full64",
        "soc_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "soc_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], text=True)),
        "inputs": [
            {
                "path": str(path.relative_to(ROOT)),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
            for path in inputs
        ],
        "binary_sha256": hashlib.sha256((build / "simv").read_bytes()).hexdigest(),
    }
    (build / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"PASS VCS build: {a.core}/{a.output}; log: {build / 'compile.log'}")
