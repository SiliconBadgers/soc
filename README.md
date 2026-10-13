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
Make and Python 3.11+. CPU/host probes also require a C++17 compiler.
Verilator is used only by `make lint`. For an existing clone,
run `./scripts/workspace.sh init`. [SETUP.md](SETUP.md) explains the CPU and
llama.cpp checks; [the workspace guide](docs/WORKSPACE.md) explains contributions
and revision updates. Component checkouts are pinned to commits, not floating
branches. The script rejects changed revisions and dirty component checkouts
before running reproducible tests.

## Source ownership

| Location | Responsibility |
|---|---|
| `rtl/`, `sim/` | Existing-core wrappers, system test assembly, modeled RAM/MMIO and error-returning engine fixtures |
| `components/architecture/` | Shared diagrams, interface specifications and architectural decisions |
| `components/rtl/` | Compute, control and memory blocks, including the shared block command package |
| `components/software/` | Workload evidence, device firmware and llama.cpp probes |
| `components/verification/` | Independent tests, including the RTL routing pilot |
| `components/physical-design/` | Synthesis flows, constraints and target wrappers |
| `components/planning/` | Current team assignments and plan |
| `experiments/` | Revision-specific combined-system evidence |

## What works

The integration harness boots upstream Ibex or CV32E40P, executes RV32IM firmware
and routes commands to RTL stubs that return `UNIMPLEMENTED`. RAM, MMIO and
descriptor access are C++ simulation models. The ggml/Qwen checks run tensor math
on the host CPU; the Qwen hook observes operations after execution. Neither CPU
is selected for the final device, and no hardware inference or synthesis result
is claimed.

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
