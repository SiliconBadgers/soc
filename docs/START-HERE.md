# System integration

SoC is the consolidated device composition and cross-repository
workspace. Follow [the workspace workflow](WORKSPACE.md), [setup](../SETUP.md)
and [integration boundaries](integration/README.md).

The [RISC-V controller guide](control/top-level-controller-spec.md) describes
the Ibex composition, generated registers, and shared control contract.
`make test-controller` runs its VCS regression;
`make lint-controller` elaborates the blocks and both core configurations.

Current active-team assignments remain in
[Planning](https://github.com/SiliconBadgers/planning/blob/main/docs/team-start.md).
This supporting workspace does not add a new team. It consumes component work
through pinned submodules. The Ibex controller advances
[SoC issue #4](https://github.com/SiliconBadgers/soc/issues/4). The controller
specification records the remaining unit-format and platform integration work.
