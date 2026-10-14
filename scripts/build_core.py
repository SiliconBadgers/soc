#!/usr/bin/env python3
"""Build the CPU integration probe with VCS; use Verilator only for lint."""

import argparse
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument("core", choices=["ibex", "cv32e40p"])
p.add_argument("--source", default="sim/core_probe.cpp")
p.add_argument("--output", default="core_probe")
p.add_argument("--link-ggml", action="store_true")
p.add_argument("--hls", action="store_true", help="Use hardware RAM/MMIO and memory transactions")
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
    "components/rtl/rtl/compute/Matrix_Unit/bpu_sa_delay.sv",
    "components/rtl/rtl/compute/Matrix_Unit/bpu_sa_pe.sv",
    "components/rtl/rtl/compute/Matrix_Unit/bpu_sa_array.sv",
    "sim/matrix_command_adapter.sv",
    "components/rtl/rtl/control/command_router.sv",
    "sim/command_router_test_top.sv",
    "rtl/riscv_wrapper.sv",
    "sim/control_path_sim_top.sv",
]
if a.hls:
    manifest_path = ROOT / "build/hls/platform/manifest.json"
    if not manifest_path.is_file():
        p.error("Run scripts/build_hls.py first")
    hls_manifest = json.loads(manifest_path.read_text())
    if (
        hls_manifest["source_sha256"]
        != hashlib.sha256((ROOT / "hls/platform_memory.cpp").read_bytes()).hexdigest()
    ):
        p.error("HLS source changed; regenerate the RTL")
    for record in hls_manifest["outputs"]:
        path = manifest_path.parent / record["path"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]:
            p.error(f"Generated HLS output changed: {path}")
    files = [
        "components/rtl/rtl/common/command_pkg.sv",
        "build/hls/platform/platform_memory.v",
        "components/rtl/rtl/compute/Matrix_Unit/bpu_sa_delay.sv",
        "components/rtl/rtl/compute/Matrix_Unit/bpu_sa_pe.sv",
        "components/rtl/rtl/compute/Matrix_Unit/bpu_sa_array.sv",
        "components/rtl/rtl/control/command_router.sv",
        "rtl/command_error_endpoint.sv",
        "rtl/matrix_memory_adapter.sv",
        "rtl/platform_bus.sv",
        "rtl/riscv_wrapper.sv",
        "rtl/soc_top.sv",
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
build = ROOT / ("build/vcs-hls" if a.hls else "build/vcs") / a.core / a.output
build.mkdir(parents=True, exist_ok=True)
testbench = "sim/hls_platform_vcs_tb.sv" if a.hls else "sim/control_path_vcs_tb.sv"
top_name = "soc_top" if a.hls else "control_path_sim_top"
if a.lint_only:
    subprocess.run(
        [
            "verilator",
            "--lint-only",
            "--assert",
            "--timescale",
            "1ns/1ps",
            "--top-module",
            top_name,
            "config/vendor.vlt",
            *(["config/hls.vlt"] if a.hls else []),
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
    if a.hls:
        cflags.append("-DHLS_PLATFORM")
        for memory in (ROOT / "build/hls/platform").glob("*.mem"):
            shutil.copy2(memory, build / memory.name)
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
        "hls_platform_vcs_tb" if a.hls else "control_path_vcs_tb",
        *vcs_opts,
        *sources,
        *files,
        testbench,
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
        ROOT / testbench,
        ROOT / "sim/sim_host.hpp",
        ROOT / ("sim/hls_host.hpp" if a.hls else "sim/matrix_memory.hpp"),
        ROOT / ("sim/hls_signals.hpp" if a.hls else "sim/sim_signals.hpp"),
        ROOT / "sim/probe_entry.hpp",
    ]
    metadata = {
        "platform": "HLS RTL" if a.hls else "C++ simulation model",
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
    if a.hls:
        metadata["hls"] = hls_manifest
    (build / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"PASS VCS build: {a.core}/{a.output}; log: {build / 'compile.log'}")
