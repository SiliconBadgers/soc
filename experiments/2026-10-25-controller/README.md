# Controller integration checks

VCS `Y-2026.03_Full64` on CAE `linux-2612` passed all four controller
compilations and all twelve simulations: four positive cases and eight deliberate
failure checks. No tests were skipped. Elapsed time was 25.513
seconds. The [final report](cae-final/summary.md), [source fingerprints and commands](cae-final/summary.json),
and linked logs record the run.

The checked sources use SoC base `fd4e8e3b61b13b3a2dee773c2755e29f2c93f784` and RTL base
`148f59cac90fb3834398df5e7c884679add4693b`, with uncommitted changes identified by SHA-256 in the report.
Pinned upstream revisions are Ibex `4dd3932a36b5af5ac002bddbe16a1b4ead1a6fd8` and
CV32E40P `6033d2b1be3295ec774d17ac4cf226faacfdeb08`.

## Checked behavior

| Positive configuration | Observed checks |
| --- | --- |
| Register bank, 4-bit counters, depth 2, 128-bit payload | 328 testbench checks; 5 reset checks; 1 full-queue COMMIT stall; 6 issue handshakes; 2 milestone-wait scenarios |
| AXI-Lite adapter | 28 native transfers; 112 stalled native-request cycles; 1 reset with a partial write pending |
| Ibex controller, 16-bit counters, depth 4, 128-bit payload, 16 KiB RAM | 6 unit-command handshakes across two firmware jobs; 17 accepted CPU data reads |
| CV32E40P controller, same configuration | 6 unit-command handshakes across two firmware jobs; 21 accepted CPU data reads |

The processor cases exercise the complete AXI host path, dependency ordering,
scoreboard waits, completion drain, interrupt acknowledgement, host access during
CPU stalls, reset/reload, RAM byte enables, and CPU instruction/data/MMIO faults.
Engine endpoints are handshake/milestone fixtures. Counts describe observed
transactions and scenario checks; they are not coverage percentages.

Eight deliberate failures checked result comparisons and required reset/stall
prerequisites. They count as passed only when their required diagnostics and
nonzero exits occur. Both processor positives finished with zero assertion
failures. CV32E40P reports an upstream unique-case warning at time zero before
reset settles; its raw log is retained.

The [first CAE attempt](cae-initial/summary.md) records the Ibex assertion failure
from speculative fetch into undefined words after a terminal jump. Fixture
images now include eight explicit NOP words after each program. The
[specification](../../docs/control/top-level-controller-spec.md#processor-and-memory)
defines the image initialization contract. The earlier
[local prerequisite failure](vcs/summary.md) is retained separately.

## Other checks

`make style` passed with Verible `v0.0-3946-g851d3ff4`, Ruff `0.16.6`, and uv
`0.12.23` for 19 SystemVerilog sources and 16 Python files. Six
[lint/elaboration configurations](lint-final/summary.md) passed with Verilator
`5.030`, including both processor configurations and the complete hierarchy.
Undriven and multiple-driver warnings were enabled and fatal. The preferred lint
version is `5.050`; the report records that mismatch. Compatibility rules are
confined to named upstream core signals. `git diff --check` passed.

The companion RTL queue regression passed two compilations and seven simulations
at depths one and three with four-bit counters. Its report is maintained with
the RTL checkout under `experiments/control/2026-10-25-command-queues/`.

Coverage, formal verification, synthesis, timing, and CDC/reset analysis were not
measured.

## Reproduce

Stage the SoC and companion RTL sources on the same CAE machine, keeping the
pinned core dependencies under `.deps/`. From the SoC checkout on CAE:

```sh
module load synopsys/vcs-mx/2026.03
python3 scripts/controller_tests.py --rtl-root ../rtl --out build/controller-cae-final --timeout 900
```

From the local SoC checkout:

```sh
make style
make lint-controller CONTROLLER_ARGS="--rtl-root ../rtl --out build/controller-lint-final"
```

The [specification](../../docs/control/top-level-controller-spec.md#rtl-and-verification-entry-points)
describes dependency setup. The JSON report records exact compiler/simulator
commands, source hashes, actual tool versions, elapsed times, and per-check log
locations. CAE staging, execution, and log retrieval used one SSH ControlMaster
connection so all operations reached the same machine.

AI assistance: OpenAI Codex; primary runtime model ID unavailable. Delegated
implementation and review used `gpt-6.1-sol`.
