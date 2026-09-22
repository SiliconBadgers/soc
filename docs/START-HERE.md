# SoC and host boundary starting material

September 22, 2026. Initial investigations for team discussion; no personal assignments or deadlines.

## Shared starting points

- [Editable architecture diagram](https://github.com/SiliconBadgers/architecture/blob/main/docs/accelerator-diagram.md) and [candidate boundaries](https://github.com/SiliconBadgers/architecture/blob/main/contracts/accelerator-boundaries.md).
- [Workload cases and source shapes](https://github.com/SiliconBadgers/architecture/blob/main/docs/workload-cases.md).
- [Measured llama.cpp report](https://github.com/SiliconBadgers/software/blob/main/experiments/llama-cpp/2026-09-22/REPORT.md) and [reproduction procedure](https://github.com/SiliconBadgers/software/blob/main/experiments/llama-cpp/2026-09-22/README.md).
- [Parallel team investigations](https://github.com/SiliconBadgers/planning/blob/main/docs/team-start.md).

The diagram and engine split are proposals. Start from available shapes and
reference cases now; use explicit parameters or stubs where decisions remain
open. Software's broader profiling study is not a prerequisite. Preserve the
source revision, assumptions, commands and limits of each result. Members and
leads can choose a different investigation that resolves a relevant uncertainty.


## First useful output

A system-boundary diagram and a host-visible transaction walkthrough using stubs
for the command engine and memory service. Show register/address decoding,
descriptor submission, status/error/IRQ, clocks/resets and platform memory access.
The host is an existing CPU; this scope does not require a custom core or ISA.

## Procedure

1. Separate host transport/register access from accelerator command sequencing. The top-level command FSM belongs to Control, not a CPU instruction decoder.
2. Write a successful command walkthrough from software submission through output visibility and acknowledgment. Keep register offsets and descriptor layout provisional.
3. Write rejected-command, outstanding-transfer fault and reset/quiescence walkthroughs with the same boundary vocabulary.
4. Identify clock-domain and reset crossings that the target actually requires. Mark unknown platform details instead of inventing a bus frequency or address map.
5. Model host accesses against engine/memory stubs; compare F2 platform needs separately from first-chip SRAM staging.

## Useful exchange and checks

Agree acceptance/completion semantics with Control and Software, transfer
visibility with Memory, and reset observability with Verification. Produce a
candidate interface table and trace demonstrating no premature completion or
reuse of live buffers. Platform-specific adaptation stays explicit in this
repository's scope even without a separate FPGA team. No board shell or full
SoC is implemented by this packet; `make test` currently reports a scaffold.
