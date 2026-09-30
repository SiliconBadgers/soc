# Project layout

The SoC superproject contains device composition and revision-pinned
component repositories:

```text
soc/
  components/
    architecture/      shared diagrams and interface types
    rtl-control/       controller implementation and experiments
    rtl-compute/       compute RTL and independent proposals
    rtl-memory/        memory and transfer implementations
    software/          workload evidence, firmware and runtime probes
    verification/      independent tests and reference models
    physical-design/   target wrappers, constraints and flows
    planning/          current assignments and plan
  rtl/integration/     existing-core wrappers and engine fixtures
  sim/                 system simulation adapters
  scripts/             initialization and build orchestration
  experiments/         dated combined-system evidence
  dependencies.json    pinned upstream sources and model checksum
  .gitmodules          component repository URLs
```

Component sources have one authoritative home. The superproject records their
commits as Git gitlinks and compiles their files directly. Build outputs and
downloaded dependencies live in ignored `build/` and `.deps/` directories.
The former `accelerator` workspace is consolidated here.

Use [WORKSPACE.md](WORKSPACE.md) for checkout, testing and component revision
updates. The shared architecture diagram remains in Architecture, and the
[current team map](https://github.com/SiliconBadgers/planning/blob/main/docs/team-start.md)
remains in Planning. Repository layout does not freeze an ABI or compute partition.
