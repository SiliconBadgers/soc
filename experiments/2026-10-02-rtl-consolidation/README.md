# Combined RTL integration regression

This run checks the SoC workspace after replacing its three RTL submodules with
one `components/rtl` checkout. The common command package and router are compiled
from RTL, firmware and probes from Software, and tests from Verification.
[results.json](results.json) records the exact source, component and dependency
revisions. Earlier experiments retain their original paths and results.

| Check | Result |
|---|---|
| Source style | Four SoC SV sources, four SoC Python scripts and three RTL SV sources pass |
| Verilator lint | Ibex and CV32E40P pass with the documented upstream waivers |
| Routing | All eight directed command cases pass |
| MAC reference | Four software tests, 261 vectors and 131,600 directed checks pass |
| Firmware and memory service | Both cores boot; all 24 latency/grant configurations pass |
| ggml MLP | Maximum absolute error 2.56841e-8 with either core |
| Qwen3.5-2B | 1,422 observed commands per core; zero final-logit difference |

## Reproduce

Check out the recorded SoC source revision, initialize its pinned submodules,
and follow [SETUP.md](../../SETUP.md) for tools, dependencies and the model.
With the required tools on PATH:

```sh
./scripts/workspace.sh init
./scripts/workspace.sh doctor
make style lint test mac-test
make -C components/rtl style
make sweep
make model-check
```

[control-sweep.json](control-sweep.json) contains all 24 service configurations.
The Qwen test uses seven prompt tokens and one decode token. Tensor operations
execute on the host CPU; the RISC-V firmware exercises the simulated command
path and receives errors from unimplemented endpoints. These checks establish
integration continuity, not hardware inference performance or a final CPU choice.
Pinned dependencies and compiled llama.cpp libraries were reused; firmware and
both Verilated core/probe executables were rebuilt. No synthesis, timing, CDC,
four-state simulation or FPGA run was performed.

## Published checkout

A fresh recursive GitHub clone at the merged component pins passed workspace
verification, prerequisites, source style, routing and MAC checks.
[published-checkout.json](published-checkout.json) records that SoC revision
and the comparison against the full regression. Only component documentation
changed between the full run and the merged pins; implementation and test
sources are identical.
