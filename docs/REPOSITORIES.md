# Repositories and current teams

| Team | Repositories / issues | Current deliverable |
|---|---|---|
| Software | [software#3](https://github.com/SiliconBadgers/software/issues/3) | Extend llama.cpp profiling and recommend boundaries from evidence. |
| Compute1 | [rtl#2](https://github.com/SiliconBadgers/rtl/issues/2) | Independent full compute-unit proposal in research/compute1/. |
| Compute2 | [rtl#2](https://github.com/SiliconBadgers/rtl/issues/2) | Independent full compute-unit proposal in research/compute2/. |
| Top-Level Control | [rtl#6](https://github.com/SiliconBadgers/rtl/issues/6), [architecture#3](https://github.com/SiliconBadgers/architecture/issues/3) | Controller diagram/walkthrough in RTL; MMIO and descriptor proposal in architecture#3. |
| Memory Control | [rtl#7](https://github.com/SiliconBadgers/rtl/issues/7) | Memory-controller diagram, interfaces and load-compute-store walkthrough. |
| Verification | [verification#2](https://github.com/SiliconBadgers/verification/issues/2), [verification#3](https://github.com/SiliconBadgers/verification/issues/3), [verification#4](https://github.com/SiliconBadgers/verification/issues/4) | Test plan, per-layer methodology and hardened Synopsys unit/integration pilots. |
| Synthesis / Physical Design | [physical-design#2](https://github.com/SiliconBadgers/physical-design/issues/2), [physical-design#3](https://github.com/SiliconBadgers/physical-design/issues/3) | One Synopsys chip baseline and synthesis coverage for every unit, with stubs. |

Compute1 and Compute2 produce independent full proposals in rtl.
Top-Level Control works in both rtl and architecture. Architecture owns
the [shared diagram](https://github.com/SiliconBadgers/architecture/blob/main/docs/accelerator-diagram.md) and shared contracts. `soc` and `planning` are supporting repositories, not additional active team assignments.

All seven active core repositories are public. Accept an invitation for write access,
follow the repo's contribution instructions and use branches/PRs for
@abhinavnandwani's review. Main requires one code-owner approval with admin bypass.

See [the maintained team map](https://github.com/SiliconBadgers/planning/blob/main/docs/team-start.md),
[contribution instructions](../CONTRIBUTING.md), and
[the existing MAC example setup](GETTING_STARTED.md). The example is not the
accelerator roadmap and does not define a custom CPU or ISA.
