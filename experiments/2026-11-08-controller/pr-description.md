## Change

Refs #4. Add a host-loadable Ibex controller with AXI4-Lite access, local RAM,
and PeakRDL-generated host and firmware register views. Firmware stages and
atomically submits Memory, Matrix, and Vector commands, waits on retained
milestone targets, and publishes completion after the queues and unit work drain.
Host status reads remain available during a blocked firmware commit or finish.

`regs/controller.rdl` supplies the register ABI, generated RTL, and C headers.
The generator locks its tool versions and checks output hashes and elaboration
parameters. The wrapper handles ownership, malformed accesses, transactional
side effects, and faults. Hardware interrupt set takes priority over W1C.

The public C header provides scalar volatile word accessors. C firmware
compiled with the locked Zig toolchain fills a queue, waits through a blocked
commit while host reads continue, and completes after dependent commands drain.
The fixture exercises initialized data, BSS, stack storage, and the generated
CSR API on real Ibex RTL.

The `controller_rtl` dependency pins the unchanged implementation from
[RTL #29](https://github.com/SiliconBadgers/rtl/pull/29). The controller adapts
its queue arrays and stops new unit-facing offers on faults while preserving
stalled offers. The existing `components/rtl` pin supplies the older MAC smoke
fixture. The shared specification is in
[RTL #32](https://github.com/SiliconBadgers/rtl/pull/32); the SoC guide documents
generation, composition, and test entry points.

## Evidence

- CAE VCS `Y-2026.03_Full64`: six compilations and nineteen simulations passed
  in 61.910 seconds, zero skipped; six positive configurations and thirteen
  deliberate failures. Inputs are deterministic.
- Tests cover 128-bit and 512-bit payloads, four-bit and 32-bit counter wrap,
  independent CSR paths, atomic enqueue, backpressure, malformed accesses,
  retained waits, drained completion, faults, and reset. Both pinned cores
  execute host-loaded firmware through the AXI controller assembly.
- The compiled C test checks five commands, 101 aligned CSR writes, all 80
  payload words through acceptance, 50 stalled commit cycles, three concurrent
  host status reads, dependency release, and completion after engine idle.
- All 153 staged source/dependency/generated-file/firmware hashes match local inputs.
  Tested SoC: `12c5eb21a6f96825d4da7fd9905dd340df6470a8`; controller RTL:
  `0a2cb4cf0d5f81f08346d1f7433d822c9e89f6dd`.
- Nine lint elaborations, 20 tooling tests, generated-output checks, and style
  checks for 21 SV and 20 Python files passed. Source and documentation
  whitespace checks passed; raw tool logs retain their original bytes. The
  tooling tests verify that four non-inlined RV32 CSR helpers emit word accesses.
- Independent bug review found the post-fault issue gap fixed by the controller
  offer gate and packed C accesses fixed by the scalar MMIO API. Final review
  found no actionable functional bugs.

Run report: `experiments/2026-11-08-controller/README.md`.
Commands, hashes, counts, and log index:
`experiments/2026-11-08-controller/cae-pr29-locked/summary.json`.

Unit interfaces use testbench models. F2 shell interrupt delivery, XPM memory
mapping, real unit decoders, and clock crossings remain platform integration
work. Coverage, formal verification, synthesis, timing, and CDC analysis were
not measured. Host-to-HBM DMA remains a separate task.

AI assistance: OpenAI Codex; primary runtime model ID unavailable. Delegated
implementation, verification, and review used `gpt-6.1-sol`.
