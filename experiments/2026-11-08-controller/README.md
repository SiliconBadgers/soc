# PeakRDL controller regression

The controller passed six VCS compilations and nineteen simulations on CAE
`linux-2614` with `Y-2026.03_Full64` in 61.910 seconds: six positive configurations
and thirteen deliberate failure checks. All planned cases ran. The
[summary and logs](cae-pr29-locked/summary.md) and
[commands, elapsed time, and source hashes](cae-pr29-locked/summary.json)
record the run.

The implementation uses separate PeakRDL host and firmware register views from
one SystemRDL source. The wrapper preserves the register ABI, keeps host access
available during blocked firmware transactions, and implements atomic command
submission, retained waits, completion, and fault handling. Faults hold new queue
offers while already-offered commands retain their ready/valid obligations.

## Tested configurations

| Configuration | Payload / counter bits | Observed activity |
| --- | --- | --- |
| Native registers | 128 / 4 | 256 checks, 5 active resets, 1 full-queue stall, 6 command issues, 2 satisfied waits. |
| Wide native registers | 512 / 32 | 186 checks, 2 active resets, 1 full-queue stall, 3 command issues, 2 satisfied waits; all 16 payload words checked. |
| AXI4-Lite | 128 / 16 | 28 transfers, 112 response-stall cycles, 1 active reset. |
| Ibex system | 128 / 16 | Host-loaded firmware issued 6 commands and made 17 CPU data reads. |
| CV32E40P system | 128 / 16 | Host-loaded firmware issued 6 commands and made 21 CPU data reads. |
| Ibex C firmware | 512 / 32 | 5 commands, 101 CSR writes, 32 CPU data reads, 50 stalled COMMIT cycles, and 3 host status reads during the stall. All 80 payload words and 10 dependency writes checked. |

Tests are deterministic. The four-bit counter test wraps through normal
increments. The 32-bit case seeds a counter at `0xfffffffe`, then publishes
increments across wrap and checks a masked wait on zero. Wide-payload tests
change staging while an offer is stalled, verify the retained record, and check
host reads during a full-queue firmware stall. The fault test accepts a retained
offer, advances dependencies, and verifies that the next head remains held.

Deliberate failures inject wrong results or omit required reset/stall scenarios.
Each passes only when its expected diagnostic and failure exit are observed.
The system tests execute real processor RTL; unit acceptance, milestones, idle,
and fault inputs come from testbench models.

### C firmware

[`csr_backpressure.c`](../../firmware/controller/csr_backpressure.c) builds
with Zig 0.16.0 for RV32IM and loads through AXI at `0x80`. Startup establishes
the stack and clears BSS. The program checks initialized data, zeroed BSS,
stack values, the register ABI, and the host job argument before submitting work.
The [build manifest](c-firmware-pr29-locked/manifest.json),
[disassembly](c-firmware-pr29-locked/firmware.dis), and
[load image](c-firmware-pr29-locked/firmware.hex)
retain the compiler inputs and output identities.

The program uses the generated scalar MMIO API through non-inlined helpers.
It fills a depth-two Memory queue, stalls on the third `COMMIT`, and resumes
when the model accepts a command. The test checks host status service during
that stall, payload stability through acceptance, both cross-queue dependencies,
and `FINISH` waiting for engine idle. Required counts include exactly five
accepted commits and 101 aligned full-word CSR writes. Deliberately omitting
the backpressure scenario or expecting the wrong result fails the run.

C-focused review found that packed register structs can produce byte accesses
through a pointer. The public generated header now exposes scalar volatile
word accessors; packed type exports describe layouts. Four separately compiled
RV32 helpers each produce exactly one `lw` or `sw`, checked by the tooling test.

## Sources and tools

The run used the following source revisions. The controller consumes the
unchanged queue implementation from [RTL #29](https://github.com/SiliconBadgers/rtl/pull/29).

| Source | Revision |
| --- | --- |
| SoC | `12c5eb21a6f96825d4da7fd9905dd340df6470a8` |
| Controller RTL dependency | `0a2cb4cf0d5f81f08346d1f7433d822c9e89f6dd` |
| Ibex | `4dd3932a36b5af5ac002bddbe16a1b4ead1a6fd8` |
| CV32E40P | `6033d2b1be3295ec774d17ac4cf226faacfdeb08` |

All 153 staged source, dependency, generated-file, and firmware fingerprints
match the local inputs in
[fingerprint-check-pr29-locked.json](fingerprint-check-pr29-locked.json). Per-configuration
manifests record SystemRDL Compiler 1.33.0, PeakRDL-regblock 1.3.1, and
PeakRDL-CHeader 1.1.0, along with the RDL, generator, configuration, and output
hashes. The runner validates those manifests before compilation.

[Tooling tests](tooling-pr29-locked.log) passed all 20 cases. Generator checks include
deterministic output and C-header layout compilation for payload/counter widths
`32/2`, `128/4`, `512/32`, and `1792/32`; missing, stale, and mismatched output;
five invalid-width cases; and freestanding scalar MMIO code generation.
The default configuration also passed `generate_controller_regs.py --check`.
Dependency tests accept the clean pinned checkout, reject a wrong revision or
tracked/untracked changes, and exercise the explicit development override.

[Lint](lint-pr29-locked/summary.md) passed nine elaborations with local Verilator 5.030.
The runner records the preferred 5.050 baseline and actual version. Narrow
waivers in `config/controller_vendor.vlt` cover generated field structures and
the pinned cores' 5.030 diagnostics. [Style checks](style-pr29-locked.log) passed
for 21 SystemVerilog and 20 Python files using pinned Verible and Ruff.

Independent bug review found the post-fault issue gap addressed by the
controller's offer gate and the packed-header access issue addressed by the
scalar API. The array adapter and gate were reviewed against the PR #29 sources.
Final review found no actionable functional bugs. Coverage, formal verification,
synthesis, timing, and CDC analysis were not measured.
F2 shell interrupt delivery, XPM mapping, unit decoders, and clock crossings
remain platform integration work.

## Reproduce

From the SoC root, fetch the locked dependencies and run the checks:

```sh
uv run --locked python scripts/fetch_dependencies.py
uv run --locked --group controller python scripts/generate_controller_regs.py --check
make test-tooling
make style
make lint-controller CONTROLLER_ARGS="--out build/controller-lint"
```

The controller test target selects the locked `controller` and `toolchain`
groups. Install LLVM tools with `llvm-objdump` on `PATH` for the firmware
disassembly. The build manifest records its version.
The runner uses `.deps/controller_rtl` at the revision in `dependencies.json`;
the older `components/rtl` pin continues to supply the MAC smoke fixture.

On CAE, load the simulator and run from the staged SoC checkout:

```sh
module load synopsys/vcs-mx/2026.03
make test-controller CONTROLLER_ARGS="--out build/controller-vcs"
```

The recorded run generated its configurations and C firmware locally and
supplied them with `--generated-root` and `--firmware-root` on CAE. It retained
one SSH ControlMaster connection for staging, compilation, simulation, and log
retrieval. The runner invoked the
selected RTL checkout's `scripts/vcs.py` through `synopsys-run`, with assertions,
timeouts, and preserved failure exit codes. The JSON report retains the exact
staged paths and commands. The earlier [baseline](baseline/summary.md),
[generated-register run](cae/summary.md), [initial C run](cae-c-initial/summary.md),
[prototype-queue C run](cae-c-firmware/summary.md), and
[PR #29 integration run](cae-pr29/summary.md) are kept for comparison.

AI assistance: OpenAI Codex; primary runtime model ID unavailable. Delegated
implementation, verification, and bug review used `gpt-6.1-sol`.
