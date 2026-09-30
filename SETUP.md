# Running the integration harness

Prerequisites: Git, Make, Python 3.11+, a C++17 compiler and Verilator. Recorded
runs used Verilator 5.050 on macOS arm64. The small RTL test needs no upstream
CPU checkout, model or Python package:

```sh
./scripts/workspace.sh test
```

Before running checks in an existing clone, initialize the pinned components:

```sh
./scripts/workspace.sh init
```

## CPU and firmware tests

Fetch the pinned sources. They stay in ignored `.deps/` directories with their
upstream licenses intact. The script refuses to overwrite a differing or dirty
checkout.

```sh
./scripts/workspace.sh deps
```

Firmware uses Zig 0.16.0 as an RV32IM cross-compiler; llama.cpp uses CMake 4.4.3.
Either install these tools normally or install local copies:

```sh
python3 -m pip install --target .deps/python ziglang==0.16.0 cmake==4.4.3
./scripts/workspace.sh cores ZIG="$PWD/.deps/python/ziglang/zig"
./scripts/workspace.sh sweep ZIG="$PWD/.deps/python/ziglang/zig"
```

`./scripts/workspace.sh cores` builds and runs both cores. `./scripts/workspace.sh sweep` runs 24 control-memory
configurations and writes `build/control-sweep.json`. To run one case directly:

```sh
build/ibex/core_probe build/firmware.bin 4 3
build/cv32e40p/core_probe build/firmware.bin 4 3
```

The trailing arguments are response latency and grant period, in cycles.
All build outputs are ignored under `build/`. Upstream CPU width warnings are
visible and nonfatal in these experimental builds; the standalone first-party
RTL test treats Verilator warnings as errors. A compiler warning about
Verilator's `-Wno-unnecessary-virtual-specifier` was also observed with Apple
Clang 17. These are simulation runs, not lint-clean or synthesis-qualified CPU
integrations.

## ggml and Qwen checks

The numerical MLP test requires no model download:

```sh
./scripts/workspace.sh graph-check ZIG="$PWD/.deps/python/ziglang/zig" \
  CMAKE="$PWD/.deps/python/cmake/data/bin/cmake"
```

For the Qwen3.5-2B test, download approximately 1.28 GB of model weights. The
script verifies the revision and SHA-256 listed in `dependencies.json`.

```sh
./scripts/workspace.sh model
./scripts/workspace.sh model-check ZIG="$PWD/.deps/python/ziglang/zig" \
  CMAKE="$PWD/.deps/python/cmake/data/bin/cmake"
```

These targets disable GPU offload, BLAS, OpenMP and native CPU tuning in the
llama.cpp build. The probe runs its inference with one CPU thread. It emits JSON
results on stdout; llama.cpp diagnostics go to stderr. No weights or downloaded
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
The local core lint and simulation evidence uses Verilator 5.050.
