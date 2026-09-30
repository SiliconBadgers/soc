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
| [docs/integration/](../docs/integration/README.md) | Integration harness, interface status, component boundaries and limitations. |

## What runs today

The [integration harness](integration/README.md) boots Ibex and CV32E40P, tests
explicitly unimplemented engine boundaries, and probes commands from ggml and
llama.cpp. Host CPU execution supplies the numerical results. This is proposed
integration evidence for [soc #4](https://github.com/SiliconBadgers/soc/issues/4),
not a selected CPU, frozen ABI or working accelerator.

See [SETUP.md](../SETUP.md) and the
[dated results](../experiments/2026-09-29-control-integration/README.md).


Follow [CONTRIBUTING.md](../CONTRIBUTING.md) before editing or committing.
