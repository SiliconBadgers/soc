#!/usr/bin/env python3
"""Check controller blocks and both pinned CPU integrations with VCS or lint."""

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def git(path, *arguments):
    return subprocess.check_output(["git", "-C", str(path), *arguments], text=True).strip()


def controller_dependency(directory, revision=None):
    """Read checkout provenance and enforce the lock when a revision is supplied."""
    if not (directory / ".git").exists():
        raise ValueError(f"Controller RTL checkout is missing: {directory}; run make deps")
    if Path(git(directory, "rev-parse", "--show-toplevel")).resolve() != directory.resolve():
        raise ValueError(f"Controller RTL path is not a checkout root: {directory}")
    actual = git(directory, "rev-parse", "HEAD")
    dirty = bool(git(directory, "status", "--porcelain"))
    if revision is not None:
        if actual != revision:
            raise ValueError(f"controller_rtl: expected {revision}, found {actual}")
        if dirty:
            raise ValueError("controller_rtl: locked dependency has local changes")
    return actual, dirty


def core_sources(core, revisions):
    directory = ROOT / ".deps" / core
    actual = git(directory, "rev-parse", "HEAD")
    if actual != revisions[core]["revision"]:
        raise ValueError(f"{core}: expected {revisions[core]['revision']}, found {actual}")
    if git(directory, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError(f"{core}: tracked dependency files have local changes")
    rtl = directory / "rtl"
    if core == "cv32e40p":
        sources = [
            Path(line.replace("${DESIGN_RTL_DIR}", str(rtl)))
            for line in (directory / "cv32e40p_manifest.flist").read_text().splitlines()
            if line.startswith("${DESIGN_RTL_DIR}") and "tb_wrapper" not in line
        ]
        return sources, [rtl / "include", directory / "bhv/include"], ["USE_CV32E40P"]
    prim = directory / "vendor/lowrisc_ip/ip/prim/rtl"
    excluded = {
        "ibex_pkg.sv",
        "ibex_cheriot_pkg.sv",
        "ibex_top.sv",
        "ibex_lockstep.sv",
        "ibex_tracer.sv",
        "ibex_top_tracing.sv",
        "ibex_trvk.sv",
        "ibex_register_file_fpga.sv",
        "ibex_register_file_latch.sv",
    }
    sources = [
        prim / name for name in ("prim_cipher_pkg.sv", "prim_util_pkg.sv", "prim_secded_pkg.sv")
    ]
    sources += [rtl / "ibex_pkg.sv", rtl / "ibex_cheriot_pkg.sv"]
    sources += [path for path in sorted(rtl.glob("*.sv")) if path.name not in excluded]
    sources += [prim / "prim_lfsr.sv"]
    return sources, [prim, directory / "vendor/lowrisc_ip/dv/sv/dv_utils"], []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rtl-root",
        type=Path,
        help="Override the locked .deps/controller_rtl checkout for development",
    )
    parser.add_argument("--out", type=Path, default=ROOT / "build/controller")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--lint-only", action="store_true")
    parser.add_argument(
        "--only",
        choices=["regs", "regs_wide", "axi", "system_ibex", "system_cv32e40p", "system_ibex_c"],
    )
    parser.add_argument(
        "--firmware-root",
        type=Path,
        help="Use prebuilt C firmware directories named after configurations",
    )
    parser.add_argument(
        "--generated-root",
        type=Path,
        help="Use pre-generated CSR directories named after each configuration",
    )
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    rtl_root = (args.rtl_root or ROOT / ".deps/controller_rtl").resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    report = {
        "mode": "lint" if args.lint_only else "simulation",
        "seed": "deterministic",
        "coverage": "Not measured",
        "configurations_planned": 0,
        "simulations_started": 0,
        "source_commit": git(ROOT, "rev-parse", "HEAD"),
        "source_dirty": bool(git(ROOT, "status", "--porcelain")),
        "rtl_root": str(rtl_root),
        "rtl_selection": "override" if args.rtl_root else "locked",
        "rtl_commit": None,
        "rtl_dirty": None,
        "dependencies": {},
        "source_sha256": {},
        "checks": [],
    }

    def execute(name, command, directory=ROOT):
        log_path = out / f"{name}.log"
        began = time.monotonic()
        try:
            with log_path.open("w") as log:
                result = subprocess.run(
                    command,
                    cwd=directory,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    timeout=args.timeout + 5,
                )
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
        except FileNotFoundError as error:
            log_path.write_text(str(error) + "\n")
            code = 127
        entry = {
            "name": name,
            "command": command,
            "exit": code,
            "log": str(log_path),
            "elapsed_seconds": time.monotonic() - began,
            "passed": code == 0,
        }
        report["checks"].append(entry)
        return entry, log_path.read_text()

    failed = False
    try:
        pins = json.loads((ROOT / "dependencies.json").read_text())
        revision = None if args.rtl_root else pins["repositories"]["controller_rtl"]["revision"]
        report["rtl_expected_commit"] = revision
        report["rtl_commit"], report["rtl_dirty"] = controller_dependency(rtl_root, revision)
        report["dependencies"]["controller_rtl"] = report["rtl_commit"]
        configurations = [
            "regs",
            "regs_wide",
            "axi",
            "system_ibex",
            "system_cv32e40p",
            "system_ibex_c",
        ]
        if args.only:
            configurations = [args.only]
        report["configurations_planned"] = len(configurations)
        report["tests_planned"] = (
            sum(
                4 if name in ("regs", "regs_wide", "axi") else 3 if name.endswith("_c") else 2
                for name in configurations
            )
            if not args.lint_only
            else 0
        )
        report["lint_baseline"] = pins["tools"]["verilator_lint"]
        inputs = [
            ROOT / "dependencies.json",
            ROOT / "scripts/controller_tests.py",
            ROOT / "config/vendor.vlt",
            ROOT / "config/controller_vendor.vlt",
            rtl_root / "scripts/vcs.py",
            rtl_root / "scripts/run_with_timeout.py",
            ROOT / "rtl/riscv_wrapper.sv",
            ROOT / "scripts/generate_controller_regs.py",
            ROOT / "scripts/build_controller_firmware.py",
            ROOT / "pyproject.toml",
            ROOT / "uv.lock",
        ]
        inputs += list((ROOT / "rtl").glob("*controller*.sv"))
        inputs += list((ROOT / "tb").glob("controller*.sv"))
        inputs += list((rtl_root / "rtl/control").glob("*.sv"))
        report["source_sha256"] = {
            str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs
        }
        for path in (ROOT / "regs").rglob("*.rdl"):
            report["source_sha256"][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (ROOT / "firmware/controller").iterdir():
            if path.is_file():
                report["source_sha256"][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        helper = [sys.executable, str(rtl_root / "scripts/vcs.py")]
        version_command = ["verilator", "--version"] if args.lint_only else [*helper, "check"]
        entry, version = execute("tool_version", version_command)
        report["tool_version"] = version.strip()
        if not entry["passed"]:
            raise ValueError(f"Tool prerequisite failed; see {entry['log']}")
        if not args.lint_only and pins["tools"]["vcs"] not in version:
            raise ValueError("VCS version does not match dependencies.json")
        if args.lint_only:
            report["lint_matches_baseline"] = pins["tools"]["verilator_lint"] in version
        queues = [
            rtl_root / "rtl/control" / f"{name}.sv"
            for name in ("command_queue", "shared_scoreboard", "command_queues")
        ]
        for configuration in configurations:
            c_firmware = configuration.endswith("_c")
            block = configuration.split("_")[0]
            top = {
                "regs": "controller_regs_tb",
                "axi": "controller_axi_lite_tb",
                "system": "controller_system_tb",
            }[block]
            if configuration == "regs_wide":
                top = "controller_generated_tb"
            if c_firmware:
                top = "controller_firmware_tb"
            directory = out / configuration
            directory.mkdir(exist_ok=True)
            payload_width = 512 if configuration == "regs_wide" or c_firmware else 128
            counter_width = (
                4
                if configuration == "regs"
                else 32
                if configuration == "regs_wide" or c_firmware
                else 16
            )
            generated = (
                args.generated_root.resolve() / configuration
                if args.generated_root
                else directory / "generated"
            )
            if not args.generated_root:
                entry, _ = execute(
                    f"{configuration}_generate",
                    [
                        sys.executable,
                        str(ROOT / "scripts/generate_controller_regs.py"),
                        "--out",
                        str(generated),
                        "--payload-width",
                        str(payload_width),
                        "--counter-width",
                        str(counter_width),
                    ],
                )
                if not entry["passed"]:
                    failed = True
                    continue
            manifest = json.loads((generated / "manifest.json").read_text())
            expected_manifest = {
                "schema": 1,
                "payload_width": payload_width,
                "counter_width": counter_width,
                "versions": pins["tools"]["controller_generators"],
                "source_sha256": hashlib.sha256(
                    (ROOT / "regs/controller.rdl").read_bytes()
                ).hexdigest(),
                "generator_sha256": hashlib.sha256(
                    (ROOT / "scripts/generate_controller_regs.py").read_bytes()
                ).hexdigest(),
            }
            for key, expected in expected_manifest.items():
                if manifest.get(key) != expected:
                    raise ValueError(f"{configuration}: generated manifest mismatch for {key}")
            expected_files = {
                "controller_config_pkg.sv",
                "controller_access_pkg.sv",
                "controller_host_pkg.sv",
                "controller_host.sv",
                "controller_firmware_pkg.sv",
                "controller_firmware.sv",
                "controller_regs.h",
                "controller_host.h",
                "controller_firmware.h",
            }
            if set(manifest.get("files", {})) != expected_files:
                raise ValueError(f"{configuration}: generated manifest has an unexpected file set")
            for name, digest in manifest["files"].items():
                path = generated / name
                actual = hashlib.sha256(path.read_bytes()).hexdigest()
                if actual != digest:
                    raise ValueError(f"{configuration}: generated file hash mismatch for {name}")
                report["source_sha256"][str(path)] = actual
            report.setdefault("generated", {})[configuration] = manifest
            generated_sources = [
                generated / name
                for name in (
                    "controller_config_pkg.sv",
                    "controller_access_pkg.sv",
                    "controller_host_pkg.sv",
                    "controller_host.sv",
                    "controller_firmware_pkg.sv",
                    "controller_firmware.sv",
                )
            ]
            for path in (generated / "manifest.json", generated / "controller_regs.h"):
                report["source_sha256"][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
            files = [
                *generated_sources,
                *queues,
                ROOT / "rtl/controller_regs.sv",
            ]
            includes, defines = [], []
            if block == "axi":
                files += [ROOT / "rtl/controller_axi_lite.sv"]
            if block == "system":
                core = configuration.removeprefix("system_").removesuffix("_c")
                sources, includes, defines = core_sources(core, pins["repositories"])
                report["dependencies"][core] = pins["repositories"][core]["revision"]
                files = [
                    *sources,
                    *files,
                    ROOT / "rtl/riscv_wrapper.sv",
                    ROOT / "rtl/controller_system.sv",
                    ROOT / "rtl/controller_axi_lite.sv",
                    ROOT / "rtl/top_level_controller.sv",
                ]
            files.append(ROOT / "tb" / f"{top}.sv")
            for path in files:
                report["source_sha256"][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
            if args.lint_only:
                command = [
                    "verilator",
                    "--lint-only",
                    "-Wwarn-UNDRIVEN",
                    "-Wwarn-MULTIDRIVEN",
                    "--timing",
                    "--assert",
                    "--timescale",
                    "1ns/1ps",
                    "--top-module",
                    top,
                    str(ROOT / "config/vendor.vlt"),
                    str(ROOT / "config/controller_vendor.vlt"),
                    *[f"-I{path}" for path in includes],
                    *[f"-D{item}" for item in defines],
                    *map(str, files),
                ]
                entry, _ = execute(f"{configuration}_lint", command, directory)
                failed |= not entry["passed"]
                if block == "system":
                    top_index = command.index("--top-module") + 1
                    command[top_index] = "top_level_controller"
                    if c_firmware:
                        command += ["-GPayloadWidth=512", "-GCounterWidth=32", "-GQueueDepth=2"]
                    entry, _ = execute(f"{configuration}_top_lint", command, directory)
                    failed |= not entry["passed"]
                continue
            run_arguments = []
            if c_firmware:
                firmware = (
                    args.firmware_root.resolve() / configuration
                    if args.firmware_root
                    else directory / "firmware"
                )
                if not args.firmware_root:
                    entry, _ = execute(
                        f"{configuration}_firmware_build",
                        [
                            sys.executable,
                            str(ROOT / "scripts/build_controller_firmware.py"),
                            "--generated",
                            str(generated),
                            "--out",
                            str(firmware),
                        ],
                    )
                    if not entry["passed"]:
                        failed = True
                        continue
                firmware_manifest = json.loads((firmware / "manifest.json").read_text())
                report["source_sha256"][str(firmware / "manifest.json")] = hashlib.sha256(
                    (firmware / "manifest.json").read_bytes()
                ).hexdigest()
                if (
                    firmware_manifest["compiler"] != f"Zig {pins['tools']['ziglang']}"
                    or firmware_manifest["entry_address"] != 128
                ):
                    raise ValueError(
                        "C firmware compiler or entry address differs from the configuration"
                    )
                if (
                    firmware_manifest["generated_manifest_sha256"]
                    != hashlib.sha256((generated / "manifest.json").read_bytes()).hexdigest()
                ):
                    raise ValueError("C firmware generated register inputs changed")
                for name, digest in firmware_manifest["sources"].items():
                    if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
                        raise ValueError(f"C firmware source changed: {name}")
                for name, digest in firmware_manifest["outputs"].items():
                    path = firmware / name
                    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                        raise ValueError(f"C firmware output changed: {name}")
                    report["source_sha256"][str(path)] = digest
                report.setdefault("firmware", {})[configuration] = firmware_manifest
                run_arguments = [
                    f"+firmware={firmware / 'firmware.hex'}",
                    f"+firmware_words={firmware_manifest['hex_words']}",
                ]
            options = [f"+incdir+{path}" for path in includes]
            options += [f"+define+{item}" for item in defines]
            command = [
                *helper,
                "--timeout",
                str(args.timeout),
                "compile",
                "-top",
                top,
                *options,
                *map(str, files),
                "-o",
                str(directory / "simv"),
            ]
            entry, _ = execute(f"{configuration}_compile", command, directory)
            if not entry["passed"]:
                failed = True
                continue
            report["simulations_started"] += 1
            entry, text = execute(
                f"{configuration}_positive",
                [
                    *helper,
                    "--timeout",
                    str(args.timeout),
                    "run",
                    str(directory / "simv"),
                    *run_arguments,
                ],
                directory,
            )
            prefix = "CONTROLLER_REGS_PASS " if block == "regs" else "RESULT "
            lines = [line for line in text.splitlines() if line.startswith(prefix)]
            fields = dict(re.findall(r"(\w+)=(\d+)", lines[0])) if len(lines) == 1 else {}
            entry["observed_counts"] = {key: int(value) for key, value in fields.items()}
            required = (
                {"checks", "resets", "stalls", "issues", "waits"}
                if block == "regs"
                else (
                    {"commands", "cpu_reads"}
                    if block == "system"
                    else {"transfers", "stalls", "resets"}
                )
            )
            if c_firmware:
                required |= {
                    "cpu_writes",
                    "stalls",
                    "host_reads",
                    "words",
                    "dependencies",
                    "commits",
                }
            entry["passed"] &= (
                len(lines) == 1
                and (block == "regs" or re.search(r"\bPASS\b", lines[0]))
                and bool(fields)
                and required <= fields.keys()
                and all(int(fields[key]) > 0 for key in required)
            )
            failed |= not entry["passed"]
            negatives = []
            if block == "regs":
                negatives = [
                    ("missing_reset=1", "reset scenario prerequisite"),
                    ("missing_stall=1", "stall scenario prerequisite"),
                    ("wrong_result=1", "expected 0000dead"),
                ]
            elif block == "axi":
                negatives = [
                    ("missing_reset=1", "MISSING_RESET"),
                    ("missing_stall=1", "MISSING_STALL"),
                    ("wrong_result=1", "WRONG_RESULT"),
                ]
            elif block == "system":
                negatives = [("inject_bad_result=1", "mismatch")]
                if c_firmware:
                    negatives.append(
                        ("missing_stall=1", "C firmware backpressure prerequisite missing")
                    )
            for plusarg, reason in negatives:
                report["simulations_started"] += 1
                entry, text = execute(
                    f"{configuration}_{plusarg.split('=')[0]}",
                    [
                        *helper,
                        "--timeout",
                        str(args.timeout),
                        "run",
                        str(directory / "simv"),
                        *run_arguments,
                        "+" + plusarg,
                    ],
                    directory,
                )
                entry["passed"] = entry["exit"] != 0 and reason in text
                entry["expected_failure"] = reason
                failed |= not entry["passed"]
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        report["error"] = str(error)
        failed = True
    report["elapsed_seconds"] = time.monotonic() - start
    simulation_suffixes = (
        "_positive",
        "_missing_reset",
        "_missing_stall",
        "_wrong_result",
        "_inject_bad_result",
    )
    simulations = [
        entry for entry in report["checks"] if entry["name"].endswith(simulation_suffixes)
    ]
    report["tests_passed"] = sum(entry["passed"] for entry in simulations)
    report["tests_failed"] = sum(not entry["passed"] for entry in simulations)
    report["tests_skipped"] = report.get("tests_planned", 0) - len(simulations)
    report["checks_passed"] = sum(entry["passed"] for entry in report["checks"])
    report["checks_failed"] = sum(not entry["passed"] for entry in report["checks"])
    report["status"] = "FAIL" if failed else "PASS"
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = [
        f"# Controller {report['mode']} checks",
        "",
        f"Status: {report['status']}",
        "",
        f"Simulations started: {report['simulations_started']}. Coverage: Not measured.",
        f"Tests planned: {report.get('tests_planned', 0)}; passed: {report['tests_passed']}; "
        f"failed: {report['tests_failed']}; skipped: {report['tests_skipped']}.",
        "",
        "| Check | Result | Log |",
        "| --- | --- | --- |",
    ]
    lines += [
        f"| {entry['name']} | {'PASS' if entry['passed'] else 'FAIL'} | "
        f"[{Path(entry['log']).name}]({Path(entry['log']).name}) |"
        for entry in report["checks"]
    ]
    if "error" in report:
        lines += ["", report["error"]]
    (out / "summary.md").write_text("\n".join(lines) + "\n")
    print(f"{report['status']}: {out / 'summary.md'}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
