# Working in SoC integration support

Retain the home for hardware composition and host-boundary integration as interfaces mature. This is a supporting repo, not an additional active team or a new CPU/ISA project.

## Before editing or committing

- Read README.md, CONTRIBUTING.md, docs/START-HERE.md and the linked issue.
- Do not commit secrets, licensed collateral, model weights or generated
  build/simulation databases.
- Use a branch and PR for @abhinavnandwani's review. Keep the issue's technical
  scope intact; scaffolding and tone changes do not authorize a new design.

## AI assistance

If you use an AI agent, report the tool and exact model ID when available in
the PR description or change summary. State when the model is unavailable;
do not guess. No additional software, hooks or setup is required.

## Evidence and boundaries

- Link the central Architecture diagram instead of copying it. Distinguish
  accepted interfaces, proposals, assumptions, real RTL and stubs.
- Preserve dated experiment results and slide baselines. Put new work alongside
  them with revisions, commands, inputs, tool versions and limitations.
- Run checks appropriate to changed behavior. Never claim an unrun licensed-tool
  check passed or that a MAC/stub test validates the full accelerator.
- Software includes workload mapping and runtime/host integration. Do not invent
  a compiler team, custom CPU core or custom ISA.

## Simulation standard

Use Synopsys VCS Y-2026.03_Full64 for every RTL simulation. Invoke the pinned
RTL component's scripts/vcs.py helper with assertions and simv -exitstatus;
missing tools, incompatible versions, failures and timeouts must fail the run.
Verilator is permitted only for lint. Verible and Ruff remain formatting/lint
tools. Do not add an alternate simulation backend. Keep CPU/host probes on the
DPI interface in sim/control_path_vcs_tb.sv and sim/sim_signals.hpp.
Record component revisions, commands, seeds, observed counts and logs in PRs.
State whether coverage was measured; passing checks do not imply coverage closure.
