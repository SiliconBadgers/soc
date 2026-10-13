# VCS simulation validation

The SoC test commands require Synopsys VCS `Y-2026.03_Full64`. Both RISC-V
configurations pass the CPU command, ggml and Qwen checks through the new
SystemVerilog DPI interface. All 24 memory-service configurations reproduce
the earlier control-path results, including boot and command cycle counts.
Verilator is used only for lint.

## Results

Measured on CAE Linux on October 13, 2026, with GCC 8.5.0 in the VCS container,
Zig 0.16.0 and CMake 4.4.3. Inputs are deterministic; there is no randomized seed.
[results.json](results.json) contains observed results, elapsed times, tool
versions and component revisions. [inputs.json](inputs.json) records source,
firmware and model SHA-256 fingerprints.

| Check | Ibex | CV32E40P |
| --- | --- | --- |
| Firmware boot | 36 cycles | 38 cycles |
| Command probe | 6/6 commands; 6 doorbells and completions | 6/6 commands; 6 doorbells and completions |
| Command latency at one-cycle memory service | 56 cycles per command | 76 cycles per command |
| Memory-service sweep | 12/12 configurations, 72 commands | 12/12 configurations, 72 commands |
| ggml MLP | 5 commands; maximum absolute error `1.32146e-8` | 5 commands; maximum absolute error `1.32146e-8` |
| Qwen3.5-2B | 7 prompt tokens + 1 decode token; 1,422 observed commands; zero logit difference | 7 prompt tokens + 1 decode token; 1,422 observed commands; zero logit difference |
| Command / ggml / Qwen run wall time | 1.981 / 2.122 / 3.271 s | 1.825 / 2.135 / 3.170 s |
| Empty firmware | Rejected; simulator and runner exit 3 | Rejected; simulator and runner exit 3 |

The memory sweep covers response latencies 1, 2, 4 and 8 cycles and grant periods
1, 2 and 3 cycles. Its complete [control-sweep.json](control-sweep.json) matches
the [historical results](../2026-09-29-control-integration/control-sweep.json).
Wall time includes the site launcher and is not an accelerator performance result.

Additional checks:

- Independent command-router test: 8 command cases passed; simulator exit 0.
- Contract → software vectors → MAC RTL → independent verification: 261 golden
  vectors and 131,600 RTL checks passed; simulator exit 0.
- An isolated test forced the exported command-ready value to `X`. The C++
  bridge detected `Unknown RTL output: cmd_ready_o`; simulator and runner exited 3.
- Five Python runner tests passed, including incomplete results, nonzero exits,
  malformed JSON and an assertion failure following a passing result.
- Verible/Ruff style checks passed. Both cores passed Verilator 5.050 lint-only
  elaboration with the documented upstream waivers.
- **Code, functional and assertion coverage: Not measured.** No coverage
  database or percentage is claimed. Check counts are not coverage metrics.

## Scope

The CPU firmware and command router execute as RTL in VCS. Accelerator endpoints
remain stubs returning `UNIMPLEMENTED`; malformed opcode/ABI cases return errors.
RAM, MMIO and descriptor access remain C++ models.

The ggml graph executes on the host CPU and is checked against an independent
scalar calculation. The Qwen test compares every final prefill/decode logit
between runs with and without metadata commands through the CPU control path.
The model's tensor arithmetic remains on the host CPU. This does not validate
hardware inference, tensor transfers, long contexts, timing, synthesis, or the
complete instruction set of either CPU.

## Reproduce

Follow [SETUP.md](../../SETUP.md) to initialize the pinned components and install
the firmware/CMake tools. The following uses local tool installs under
`.deps/python`; omit the Make variables if they are already on `PATH`.

```sh
module load synopsys/vcs-mx/2026.03
./scripts/workspace.sh init
./scripts/workspace.sh doctor
./scripts/workspace.sh deps
./scripts/workspace.sh test
./scripts/workspace.sh mac-test
./scripts/workspace.sh cores ZIG="$PWD/.deps/python/ziglang/zig"
./scripts/workspace.sh sweep ZIG="$PWD/.deps/python/ziglang/zig"
./scripts/workspace.sh failure-check ZIG="$PWD/.deps/python/ziglang/zig"
./scripts/workspace.sh graph-check ZIG="$PWD/.deps/python/ziglang/zig" \
  CMAKE="$PWD/.deps/python/cmake/data/bin/cmake"
./scripts/workspace.sh model
./scripts/workspace.sh model-check ZIG="$PWD/.deps/python/ziglang/zig" \
  CMAKE="$PWD/.deps/python/cmake/data/bin/cmake"
python3 -m unittest discover -s scripts -p 'test_*.py'
make style
make lint
```

`model` downloads and checksum-verifies the pinned Qwen3.5-2B Q4_K_M file.
Builds and runs retain logs, elapsed times, source fingerprints and JSON summaries
under `build/router/vcs/`, `build/vcs/`, `build/sweep/` and `build/vcs-negative/`.
The MAC run retains its evidence in `components/verification/build/mac/vcs/`.
The failure regression preserves existing evidence; repeat it with
`python3 scripts/check_vcs_failures.py --out build/vcs-negative-2`.

The runner requires successful results and a zero simulator exit. Missing tools,
failed builds, incomplete output, unknown active RTL signals and timeouts fail
the run. There is no alternate simulator backend. GitHub CI checks source style
and runner logic; licensed simulation is performed separately on CAE.

## DPI and compiler compatibility

The [DPI context-task pattern](https://www.doulos.com/knowhow/systemverilog/systemverilog-dpi-tutorial)
lets the C++ host call a timed SystemVerilog task. Each call advances one settled
simulation phase. Packed four-state outputs retain unknown bits until the host
checks whether the current transaction requires them.

The llama.cpp build uses the same GCC/G++ environment as VCS. It links GCC 8's
separate C++17 filesystem library and disables CMake's host-linker dependency
flags when using the older container linker. The firmware, numerical reference
and software probe sources retain their existing behavior and ownership.
