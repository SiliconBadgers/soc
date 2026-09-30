# SoC integration support

Retain the home for hardware composition and host-boundary integration as interfaces mature. This is a supporting repo, not an additional active team or a new CPU/ISA project.

## Start here

1. Read [the current assignment and artifact locations](docs/START-HERE.md).
2. Work on a branch and open a PR for `@abhinavnandwani` using
   [CONTRIBUTING.md](CONTRIBUTING.md). Main requires a code-owner approval;
   admins can bypass.

## Repository structure

| Location | Purpose |
|---|---|
| [rtl/integration/](rtl/integration/) | Top-level command routing, existing-core wrappers and replaceable engine stubs. |
| [sim/](sim/) and [firmware/](firmware/) | CPU boot, command and llama.cpp integration probes. |
| [docs/integration/](docs/integration/README.md) | Interface status, component boundaries and limitations. |
| [experiments/](experiments/) | Dated results with pinned inputs and reproduction instructions. |

## Current material and scope

A runnable integration harness boots Ibex and CV32E40P and exercises stub
commands through firmware. Every datapath stub returns an explicit
`UNIMPLEMENTED` result. A small ggml numerical test and a Qwen3.5-2B CPU
observation test connect software to that control path. Tensor computation
remains on the host; no working accelerator or synthesis result is claimed.

Run `make test` for the standalone RTL checks. See [SETUP.md](SETUP.md) for the
CPU, memory-service sweep and llama.cpp tests, and the
[recorded results](experiments/2026-09-29-control-integration/README.md).

[Shared diagram](https://github.com/SiliconBadgers/architecture/blob/main/docs/accelerator-diagram.md) · [Software evidence](https://github.com/SiliconBadgers/software/tree/main/experiments/llama-cpp/2026-09-22)

[CHARTER.md](CHARTER.md) and [OBJECTIVES.md](OBJECTIVES.md) describe the
longer-term purpose. Current issues and the starting guide specify the work
assigned now. [SETUP.md](SETUP.md) describes runnable checks and their prerequisites.
