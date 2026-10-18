# SiliconBadgers accelerator system

This repository composes the device hardware and pins the component repositories
used to build and test it. It consolidates hardware composition with the cross-repository system
workspace. Compute, control and memory blocks share the RTL repository.
Architecture, Software, Verification and Physical Design own their respective
component sources.

## Start

```sh
git clone --recurse-submodules https://github.com/SiliconBadgers/soc.git
cd soc
./scripts/workspace.sh verify
./scripts/workspace.sh test
```

RTL simulation requires Synopsys VCS `Y-2026.03_Full64` on licensed Linux,
Make, Python 3.11+ and uv 0.12.23+. CPU/host probes also require a C++17 compiler.
Verilator is used only by `make lint`. For an existing clone,
run `./scripts/workspace.sh init`. [SETUP.md](SETUP.md) explains the CPU and
llama.cpp checks; [the workspace guide](docs/WORKSPACE.md) explains contributions
and revision updates. Component checkouts are pinned to commits, not floating
branches. The script rejects changed revisions and dirty component checkouts
before running reproducible tests.

## Source ownership

| Location | Responsibility |
|---|---|
| `rtl/`, `sim/` | Existing-core wrappers, system test assembly, modeled RAM/MMIO, the matrix-array adapter and remaining engine fixtures |
| `components/architecture/` | Shared diagrams, interface specifications and architectural decisions |
| `components/rtl/` | Compute, control and memory blocks, including the shared block command package |
| `components/software/` | Workload evidence, device firmware and llama.cpp probes |
| `components/verification/` | Independent tests, including the RTL routing pilot |
| `components/physical-design/` | Synthesis flows, constraints and target wrappers |
| `components/planning/` | Current team assignments and plan |
| `experiments/` | Revision-specific combined-system evidence |

## What works

The integration harness boots upstream Ibex or CV32E40P, executes RV32IM firmware
and routes signed INT8 matrix commands to Adam Shebani’s systolic-array RTL.
The adapter loads tensors from modeled RAM and writes signed INT32 results back
before reporting success. Vector, state and memory endpoints remain stubs.
RAM, MMIO and descriptor access are C++ simulation models. The ggml/Qwen checks
run tensor math on the host CPU; the Qwen hook observes operations after execution. Neither CPU
is selected for the final device, and no hardware inference or synthesis result
is claimed.

Run `make matrix-check` for the CPU-to-array regression. It checks arithmetic,
strides, rejected commands, completion stalls and reset on both cores across
24 instruction/data memory configurations. See the
[matrix integration report](experiments/2026-10-13-matrix-integration/README.md)
for results and limits. The adapter is a simulation fixture, not a production
DMA or SRAM interface.

The CPU/llama.cpp harness uses a VCS DPI interface. Both cores pass the six-command
probe, all 24 memory-service configurations, the ggml numerical check and the
Qwen3.5-2B logit comparison. Invalid firmware and unknown active DPI outputs
produce failing simulator exits. See the [VCS validation report](experiments/2026-10-13-vcs-migration/README.md)
for measured counts, source fingerprints and reproduction commands. Code,
functional and assertion coverage have not been measured.

The [integration guide](docs/integration/README.md) documents behavior and limits.
The preserved [original experiment](experiments/2026-09-29-control-integration/ORIGIN.md)
identifies the earlier SoC source revision. New runs are recorded separately.
The existing small MAC pipeline remains available through
`./scripts/workspace.sh mac-test`.

[Shared architecture](https://github.com/SiliconBadgers/architecture/blob/main/docs/accelerator-diagram.md)
· [Current teams](https://github.com/SiliconBadgers/planning/blob/main/docs/team-start.md)
· [Contributing](CONTRIBUTING.md)
