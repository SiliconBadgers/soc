# soc/tb

Local system-interface models and checks associated with composed hardware.

Run `make test-controller` from the SoC root for register, AXI-Lite, and firmware
tests on Ibex and CV32E40P. The [controller guide](../docs/control/top-level-controller-spec.md#rtl-and-verification-entry-points)
describes prerequisites, dependency selection, and result paths. `make lint-controller`
elaborates the same testbenches and the complete controller hierarchy.

This is a suggested home for work supporting the [charter](../CHARTER.md) and
[objectives](../OBJECTIVES.md). The team can reorganize or extend it as its work
develops. A directory’s presence does not assign a task or require an artifact.
