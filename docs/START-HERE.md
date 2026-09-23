# SoC integration support: current work

Retain the home for hardware composition and host-boundary integration as interfaces mature. This is a supporting repo, not an additional active team or a new CPU/ISA project.

## Assignment

No additional team assignment is created here. Support the [current seven-team work](https://github.com/SiliconBadgers/planning/blob/main/docs/team-start.md).

1. Follow the central diagram and shared register/descriptor work in architecture. Top-Level Control currently owns that proposal across architecture and rtl-control.
2. Keep future integration configurations, external-host assumptions, clocks/resets and real-versus-stub inventories explicit. Reference component RTL from its owning repository.
3. Do not duplicate a register map or add a separate implementation assignment through scaffold changes.

## Starting evidence

- [Central diagram](https://github.com/SiliconBadgers/architecture/blob/main/docs/accelerator-diagram.md)
- [Recorded Software profiling package](https://github.com/SiliconBadgers/software/tree/main/experiments/llama-cpp/2026-09-22)
- [Slide register maps](https://github.com/SiliconBadgers/architecture/blob/main/docs/register-maps.md) (preserved slide baseline from [architecture PR #2](https://github.com/SiliconBadgers/architecture/pull/2))

## Artifact locations

| Location | What belongs here |
|---|---|
| [docs/integration/](../docs/integration/README.md) | Future integration notes, revision manifests and host-boundary walkthroughs. Link accepted architecture contracts and state assumptions. |

## What runs today

A documentation/RTL scaffold exists. No composed accelerator or SoC-level pass is claimed.


Follow [CONTRIBUTING.md](../CONTRIBUTING.md) before editing or committing.
