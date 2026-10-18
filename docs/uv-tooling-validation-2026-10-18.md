# uv tooling validation, 2026-10-18

## Scope and source

Tooling-only migration based on `ef6b75ae1d891b9b966c2cc073a3c73072a406d1`. The PR description identifies the
published head; GitHub Actions validates that exact head. No SystemVerilog design,
testbench, simulator version, or hardware interface changed.

Local tools: uv 0.12.23, CPython 3.12.14, Ruff 0.16.6, Linux x86_64.
CI selects Python 3.11 and the same uv/Ruff versions. The required simulation
baseline remains VCS Y-2026.03_Full64. Verible remains v0.0-3946-g851d3ff4.

## Results

- Python tooling tests: 13 run, 13 passed, 0 failed, 0 runtime skips;
  elapsed 0.016 seconds for the recorded suite.
- `uv lock --check`, `make setup`, and `uv sync --locked --group dev`: passed.
- Ruff lint and format checks: passed. `git diff --check`: passed.
- A copied project's version was intentionally changed without updating its lock:
  `uv run --locked --offline` refused to run, returned nonzero, and left the
  lockfile unchanged. The intended command was not executed.
- Licensed VCS simulations: 0 run. Hardware transactions/vectors checked: 0.
- Hardware coverage, formal, synthesis, timing and CDC/reset analysis: not measured.
- Full local Verible/source-style validation: unavailable; use exact-head CI.

The thirteen tests comprise six existing simulator-result checking tests,
four uv Make-routing checks, and three toolchain-selection/override checks.
The optional toolchain group was actually synced locally; `python-zig version`
returned `0.16.0` and `cmake --version` returned `4.4.3`. No component submodule,
workspace manifest, or external dependency revision changed. The pinned legacy
MAC workspace path remains tied to its existing component revisions.

## Reproduction

From a fresh checkout of the PR head, with uv 0.12.23 and Python 3.11+:

```sh
uv lock --check
make setup
uv sync --locked --group dev
make test-tooling
uv run --locked --group dev ruff check scripts
uv run --locked --group dev ruff format --check scripts
```

With the pinned Verible executables on PATH, run the aggregate CI checks:

```sh
make style
make test-tooling
```

For RTL shell syntax, run `bash -n tb/compute/Matrix_Unit/run_tests.sh` in the RTL
checkout. For SoC's optional toolchain, run `make setup-toolchain`,
`uv run --locked --group toolchain python-zig version`, and
`uv run --locked --group toolchain cmake --version` in the SoC checkout.

Tests have bounded subprocess timeouts and preserve failing exit codes. CI logs
are linked from the PR checks. Licensed simulation still requires the documented
CAE/native VCS installation; fixture results do not replace that validation.
