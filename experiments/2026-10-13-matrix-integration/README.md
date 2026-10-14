# RISC-V to matrix-array validation

Ibex and CV32E40P now submit matrix commands that execute on Adam Shebani’s
unmodified INT8 systolic-array RTL from [RTL #14](https://github.com/SiliconBadgers/rtl/pull/14).
A simulation adapter reads input tensors from modeled RAM, drives the array,
and stores its INT32 results before firmware receives a successful completion.
The array performs the multiplication; C++ supplies memory and an independent
scalar reference.

This advances [SoC #4](https://github.com/SiliconBadgers/soc/issues/4).
The [adapter contract](../../docs/integration/README.md#matrix-array-adapter)
documents the test format and memory map. Adam’s sources and all component pins
are unchanged.

## Matrix results

Measured on CAE Linux on October 13, 2026 using VCS `Y-2026.03_Full64`,
container GCC 8.5.0 and Zig 0.16.0. All inputs are deterministic.
[The complete sweep](matrix-sweep.json) contains each observed result.

| Check | Ibex | CV32E40P |
| --- | --- | --- |
| CPU memory-service configurations | 12/12 passed | 12/12 passed |
| Successful matrix commands | 96 | 96 |
| Exact INT32 output values checked | 4,812 | 4,812 |
| Invalid/unsupported commands rejected | 180 | 180 |
| Reset during active array traffic, followed by a fresh command | 12/12 passed | 12/12 passed |
| Cycles for the eight valid commands at latency 1 / grant period 1 | 828 | 988 |
| Completion stall cycles in that same run | 146 | 178 |
| Deliberately incorrect first golden value | Detected; simulator and runner exit 3 | Detected; simulator and runner exit 3 |

Each core runs all combinations of instruction/data response latencies 1, 2,
4 and 8 cycles and grant periods 1, 2 and 3 cycles. The cycle totals include
firmware submission, array work and completion handling for eight differently
shaped commands. They are not single-tile latency or throughput measurements.
Tensor reads and writes have no modeled bus delay or contention.

Each configuration checks:

- Eight valid commands: three 8×8×8 signed-input patterns, a 3×5×7 case with
  padded strides, a 1×1×1 case, an 8×16×8 case, a 1×1×8 result ending exactly
  at the tensor-memory boundary, and another 8×8×8 after reset. Dimensions
  are listed as M×N×K. Patterns include both `-128 × -128` and `127 × -128`.
- Exact output-write and accepted-B-column counts, sequence IDs and completion
  status. Every byte of the tensor region is compared against a snapshot with
  only the expected C results changed, including input buffers and padding.
- Thirteen invalid layouts: unsupported/zero dimensions, short strides,
  unaligned C, reserved or out-of-range addresses, overflowing extents and C
  overlapping either input. They must cause no tensor read or write. Unsupported
  format and ABI add two more rejection cases.
- Reset after the real array accepts its first B column, before any C write.
  No cancelled output or completion may appear; the next command must succeed.
- Completions held while firmware polls and acknowledges them. The adapter’s
  assertion checks that the completion remains stable while stalled.

The first reset experiment exposed overlap between the test tensor range and
the firmware stack. The validated memory map reserves `[0xf000, 0x10000)` for
the stack and limits tensors to `[0x3000, 0xf000)`.

## Regression checks

[regression.json](regression.json) records the existing CPU, ggml and Qwen checks
with the matrix adapter enabled. The independent router test still uses its
error-stub configuration. The new control-memory sweep exactly matches the
[preserved VCS baseline](../2026-10-13-vcs-migration/control-sweep.json);
`regression.json` records the comparison and the new output’s checksum.

- Router: eight command cases passed.
- Both cores: six-command probe and all 24 control-memory configurations passed.
- ggml MLP: five commands per core; maximum absolute error `1.32146e-8`.
- Qwen3.5-2B: seven prompt tokens, one decode token and 1,422 observed commands
  per core; zero maximum logit difference.
- Empty firmware on each core and an injected unknown command-ready value:
  detected with simulator and runner exit 3.
- Six Python result-validation tests, Verible/Ruff checks and Verilator 5.050
  lint-only elaboration for both cores passed. No new vendor waivers were added.
- **Code, functional and assertion coverage: Not measured.** Counts are observed
  test results, not coverage percentages.

## Reproduce

Initialize the pinned components and dependencies using [SETUP.md](../../SETUP.md).
With the documented local Zig installation:

```sh
module load synopsys/vcs-mx/2026.03
./scripts/workspace.sh matrix-check ZIG="$PWD/.deps/python/ziglang/zig"
```

This builds both CPU matrix probes and runs all 24 configurations plus the two
corrupted-reference checks. It fails on missing scenarios, numerical mismatch,
simulator errors or unexpected success of a negative test. Logs and summaries
are in `build/matrix-regression/`; compile logs and input fingerprints are in
`build/vcs/<core>/matrix_probe/`. Existing regression output is preserved.
To repeat using the compiled probes:

```sh
python3 scripts/check_matrix.py --out build/matrix-regression-2
```

For the existing-path regressions:

```sh
./scripts/workspace.sh test
./scripts/workspace.sh sweep ZIG="$PWD/.deps/python/ziglang/zig"
./scripts/workspace.sh failure-check ZIG="$PWD/.deps/python/ziglang/zig"
./scripts/workspace.sh model-check ZIG="$PWD/.deps/python/ziglang/zig" \
  CMAKE="$PWD/.deps/python/cmake/data/bin/cmake"
python3 -m unittest discover -s scripts -p 'test_*.py'
make style
make lint
```

Fetch the checksum-verified Qwen model with `./scripts/workspace.sh model` first
if it is absent. Model arithmetic remains on the host CPU in those tests.

## Revisions and limits

The VCS builds used a working tree based on SoC
`db85e4f6fe386368899451ff53be47e171faee41`.
[inputs.json](inputs.json) identifies the exact tested RTL/C++ contents and
simulator binaries by SHA-256; these source fingerprints were checked against
the published files. [regression.json](regression.json) also records component
revisions and firmware/model hashes.

The matrix adapter supports signed INT8 A/B and INT32 C, M/K up to 8, and N up
to 16 using test format `0xffff0001`. It does not implement the proposed INT4
format, scaling, accumulation across K tiles or automatic larger-matrix tiling.
RAM, MMIO and descriptor access remain simulation models. The adapter uses DPI
and is not synthesizable. The next memory integration must add real requests,
responses, stalls and handling for reset with partially completed writes.
The current reset test occurs before the first output write.

No FPGA/ASIC area, timing, bandwidth, inference speed or hardware Qwen result
is established by this experiment. Neither RISC-V core is selected for the
final system.
