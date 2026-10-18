# Running the integration harness

## Python tooling with uv

Install [uv](https://docs.astral.sh/uv/getting-started/installation/) 0.12.23
or newer (CI uses exactly 0.12.23), then run from this checkout:

```sh
make setup
make test-tooling
make style
```

Python 3.11+ is required. `uv.lock` is committed; Make and the documented Python
commands use `uv run --locked`, so a stale lockfile fails instead of changing
versions silently. The project is tooling-only and is not installed as a package.
The default environment needs no third-party packages. Style/format select the
`dev` group, which pins Ruff 0.16.6; Verible remains a separately installed tool.
No virtual-environment activation or global Ruff installation is required.
Use `UV=/path/to/uv` and `PYTHON=/path/to/python` to override executable paths;
use `UV_PYTHON=3.11` to choose the interpreter uv provisions for `.venv`.
After an intentional dependency edit, run `uv lock`, review and commit the
lockfile, and rerun the relevant checks. Do not edit `uv.lock` by hand.

Synopsys VCS `Y-2026.03_Full64` is required for all RTL simulation.
Use licensed Linux with Git, Make, Python 3.11+ and a C++17 compiler. On CAE:

```sh
module load synopsys/vcs-mx/2026.03
./scripts/workspace.sh init
./scripts/workspace.sh doctor
./scripts/workspace.sh test
```

Run Make and Python on the host. The pinned RTL component's `scripts/vcs.py`
uses `synopsys-run` on CAE or native VCS on another licensed installation.
`VCS_LAUNCHER` selects a site launcher; an empty value selects native execution.
It checks the exact version, enables assertions and runs `simv -exitstatus`.
Compilation and simulation each have a 900-second timeout. There is no alternate
simulator fallback. The routing test needs no upstream CPU or model download.
Its compile/run logs are in `build/router/vcs/`.

## CPU and firmware tests

Fetch the pinned sources. They stay in ignored `.deps/` directories with their
upstream licenses intact. The script refuses to overwrite a differing or dirty
checkout.

```sh
./scripts/workspace.sh deps
```

Firmware uses Zig 0.16.0 as an RV32IM cross-compiler; llama.cpp uses CMake 4.4.3.
The opt-in `toolchain` group installs both exact versions. Build targets select
it automatically; preinstall it if desired:

```sh
make setup-toolchain
./scripts/workspace.sh cores
./scripts/workspace.sh sweep
```

The Zig wheel provides `python-zig`, used by the Make default. `CMAKE` defaults
to the locked `cmake` entry point. Explicit `ZIG=/path/to/zig` and
`CMAKE=/path/to/cmake` overrides remain supported. Python-only checks do not
install the toolchain group. Verify tools with:

```sh
uv run --locked --group toolchain python-zig version
uv run --locked --group toolchain cmake --version
```

`./scripts/workspace.sh cores` builds and runs both cores. `./scripts/workspace.sh sweep` runs 24 control-memory
configurations and writes `build/control-sweep.json`. To run one case directly:

```sh
uv run --locked python scripts/run_core.py ibex --latency 4 --grant-period 3
uv run --locked python scripts/run_core.py cv32e40p --latency 4 --grant-period 3
```

Latency and grant period are measured in cycles. Each probe is compiled into
`build/vcs/<core>/<probe>/simv`. The run helper retains `run.log`, elapsed time
and `summary.json`, and requires successful JSON results and a zero simulator
exit. Sweep runs have separate log folders under `build/sweep/`.

The C++ host uses a SystemVerilog DPI context task to advance settled simulator
phases. Unknown active control/address/result signals fail the probe rather than
being silently converted to zero. RAM and MMIO remain simulation models; the
matrix endpoint uses real INT8 array RTL; other endpoints remain error-returning stubs.

Run `make failure-check` to verify that empty firmware fails on both cores and
that an injected unknown command-ready output fails across the DPI interface.
The unknown-output case uses an isolated copy under `build/vcs-negative/` and
does not modify the source design. All three cases must return simulator and
runner exit status 3. To repeat without overwriting earlier evidence, run
`uv run --locked python scripts/check_vcs_failures.py --out build/vcs-negative-2`.

## CPU-to-matrix-array regression

```sh
./scripts/workspace.sh matrix-check
```

This builds the matrix probe for both cores, then runs 24 instruction/data
memory configurations and two deliberately incorrect golden-result checks.
Each normal run requires eight successful matrix commands, 401 exact INT32
results, 15 rejected commands, a reset after the first B column is accepted,
and stalled completions. The whole tensor-memory region is checked for stray
writes. Each corrupted-result run must fail with simulator and runner exit 3.

Evidence is retained in `build/matrix-regression/`. Existing evidence is not
overwritten by the regression script. To rerun compiled probes:

```sh
uv run --locked python scripts/check_matrix.py --out build/matrix-regression-2
uv run --locked python scripts/run_core.py ibex --probe matrix_probe --latency 4 --grant-period 3
```

The [adapter contract](docs/integration/README.md#matrix-array-adapter) defines
supported shapes, test format, strides, bounds and reset behavior. These checks
exercise real arithmetic, but tensor reads and writes consume no bus cycles;
they do not measure accelerator throughput or SRAM bandwidth.

## ggml and Qwen checks

The numerical MLP test requires no model download:

```sh
./scripts/workspace.sh graph-check
```

For the Qwen3.5-2B test, download approximately 1.28 GB of model weights. The
script verifies the revision and SHA-256 listed in `dependencies.json`.

```sh
./scripts/workspace.sh model
./scripts/workspace.sh model-check
```

The llama.cpp target uses the same compiler environment as VCS. On CAE,
compiler wrappers invoke GCC/G++ inside `synopsys-run`; this avoids linking
host libraries built against a newer C++ runtime into the simulator container.
The script links GCC 8's separate C++17 filesystem library when needed and
disables host-linker dependency flags that the older container linker lacks.
CMake itself runs on the host. These targets disable GPU offload, BLAS, OpenMP
and native CPU tuning in the llama.cpp build. The probe runs its inference with one CPU thread. The run helper emits a JSON summary and retains the simulator and llama.cpp
output in `run.log`. No weights or downloaded
third-party source belong in a commit.

For scope, interfaces, limitations and next component work, read the
[integration guide](docs/integration/README.md). For the broader checkout
layout, see the [workspace guide](https://github.com/SiliconBadgers/soc/blob/main/docs/GETTING_STARTED.md).

## Formatting and lint

`make format` applies Verible and Ruff formatting to the paths in `style.json`,
within this repository. Run `make style` in each component repository for
its sources; component checks are not folded into the SoC style job. `make style`
checks formatting and style without changing files. `make lint` elaborates
both pinned cores with Verilator, with warnings fatal except the reviewed
upstream-only entries in `config/vendor.vlt`. Run `make deps` first if needed.
The style CI job does not download CPU dependencies or model weights.

Verible v0.0-3946-g851d3ff4 and Ruff 0.16.6 are pinned in style CI.
The lint baseline is Verilator 5.050. Historical experiments retain their
recorded tool versions. Current simulation requires VCS. Source-style CI does
not claim a licensed simulation pass.
