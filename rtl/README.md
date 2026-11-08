# soc/rtl

System composition, host interfaces and interconnect implementations.

[`top_level_controller.sv`](top_level_controller.sv) assembles the RISC-V controller,
AXI-Lite host transport, local firmware RAM, registers, and command queues. The
[controller guide](../docs/control/top-level-controller-spec.md) describes
the generated registers and links the shared control contract.

This is a suggested home for work supporting the [charter](../CHARTER.md) and
[objectives](../OBJECTIVES.md). The team can reorganize or extend it as its work
develops. A directory’s presence does not assign a task or require an artifact.
