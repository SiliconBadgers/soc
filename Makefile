UV ?= uv
PYTHON ?= python3
RUN_PYTHON = "$(UV)" run --locked "$(PYTHON)"
ZIG ?= python-zig
CMAKE ?= cmake
CORES := ibex cv32e40p
MODEL := .deps/models/Qwen3.5-2B-Q4_K_M.gguf

.PHONY: test deps model firmware cores llama graph-check model-check sweep failure-check matrix-check

test:
	$(RUN_PYTHON) scripts/run_router.py

deps:
	$(RUN_PYTHON) scripts/fetch_dependencies.py

model:
	$(RUN_PYTHON) scripts/fetch_dependencies.py --model

firmware:
	mkdir -p build
	ZIG_GLOBAL_CACHE_DIR="$(CURDIR)/build/zig-cache" "$(UV)" run --locked --group toolchain "$(ZIG)" cc -target riscv32-freestanding -mcpu=generic_rv32+m -mabi=ilp32 -nostdlib -ffreestanding -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -O2 -Wl,-T,components/software/integration/firmware/link.ld components/software/integration/firmware/start.S components/software/integration/firmware/probe.c -o build/firmware.elf
	ZIG_GLOBAL_CACHE_DIR="$(CURDIR)/build/zig-cache" "$(UV)" run --locked --group toolchain "$(ZIG)" objcopy -O binary build/firmware.elf build/firmware.bin

cores: firmware
	$(foreach core,$(CORES),$(RUN_PYTHON) scripts/build_core.py $(core) && $(RUN_PYTHON) scripts/run_core.py $(core) &&) true

matrix-check: firmware
	$(foreach core,$(CORES),$(RUN_PYTHON) scripts/build_core.py $(core) --source sim/matrix_probe.cpp --output matrix_probe &&) true
	$(RUN_PYTHON) scripts/check_matrix.py

llama:
	"$(UV)" run --locked --group toolchain "$(PYTHON)" scripts/build_llama.py --cmake "$(CMAKE)"

graph-check: firmware llama
	$(foreach core,$(CORES),$(RUN_PYTHON) scripts/build_core.py $(core) --source components/software/integration/llama_probe.cpp --output llama_probe --link-ggml && $(RUN_PYTHON) scripts/run_core.py $(core) --probe llama_probe &&) true

model-check: graph-check
	$(foreach core,$(CORES),$(RUN_PYTHON) scripts/run_core.py $(core) --probe llama_probe --model $(MODEL) &&) true

sweep: cores
	$(RUN_PYTHON) scripts/sweep.py --output build/control-sweep.json

failure-check: cores
	$(RUN_PYTHON) scripts/check_vcs_failures.py

.PHONY: doctor mac-test
doctor:
	$(RUN_PYTHON) workspace.py doctor
mac-test:
	$(RUN_PYTHON) workspace.py test

.PHONY: style format
style:
	"$(UV)" run --locked --group dev "$(PYTHON)" scripts/check_style.py

format:
	"$(UV)" run --locked --group dev "$(PYTHON)" scripts/check_style.py --fix

.PHONY: lint
lint:
	$(RUN_PYTHON) scripts/build_core.py ibex --lint-only
	$(RUN_PYTHON) scripts/build_core.py cv32e40p --lint-only

.PHONY: test-tooling
test-tooling:
	$(RUN_PYTHON) -m unittest discover -s scripts -p 'test_*.py'

.PHONY: setup setup-toolchain
setup:
	"$(UV)" sync --locked

setup-toolchain:
	"$(UV)" sync --locked --group toolchain
