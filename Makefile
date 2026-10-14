PYTHON ?= python3
ZIG ?= zig
CMAKE ?= cmake
CORES := ibex cv32e40p
MODEL := .deps/models/Qwen3.5-2B-Q4_K_M.gguf
BAMBU ?= bambu

.PHONY: test deps model firmware cores llama graph-check model-check sweep failure-check matrix-check

test:
	$(PYTHON) scripts/run_router.py

deps:
	$(PYTHON) scripts/fetch_dependencies.py

model:
	$(PYTHON) scripts/fetch_dependencies.py --model

firmware:
	mkdir -p build
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/build/zig-cache $(ZIG) cc -target riscv32-freestanding -mcpu=generic_rv32+m -mabi=ilp32 -nostdlib -ffreestanding -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -O2 -Wl,-T,components/software/integration/firmware/link.ld components/software/integration/firmware/start.S components/software/integration/firmware/probe.c -o build/firmware.elf
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/build/zig-cache $(ZIG) objcopy -O binary build/firmware.elf build/firmware.bin

cores: firmware
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) && $(PYTHON) scripts/run_core.py $(core) &&) true

matrix-check: firmware
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) --source sim/matrix_probe.cpp --output matrix_probe &&) true
	$(PYTHON) scripts/check_matrix.py

llama:
	$(PYTHON) scripts/build_llama.py --cmake "$(CMAKE)"

graph-check: firmware llama
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) --source components/software/integration/llama_probe.cpp --output llama_probe --link-ggml && $(PYTHON) scripts/run_core.py $(core) --probe llama_probe &&) true

model-check: graph-check
	$(foreach core,$(CORES),$(PYTHON) scripts/run_core.py $(core) --probe llama_probe --model $(MODEL) &&) true

sweep: cores
	$(PYTHON) scripts/sweep.py --output build/control-sweep.json

failure-check: cores
	$(PYTHON) scripts/check_vcs_failures.py

.PHONY: doctor mac-test
doctor:
	$(PYTHON) workspace.py doctor
mac-test:
	$(PYTHON) workspace.py test

.PHONY: style format
style:
	$(PYTHON) scripts/check_style.py

format:
	$(PYTHON) scripts/check_style.py --fix

.PHONY: lint
lint:
	$(PYTHON) scripts/build_core.py ibex --lint-only
	$(PYTHON) scripts/build_core.py cv32e40p --lint-only

.PHONY: hls hls-contract hls-check hls-workload-check hls-lint
hls:
	$(PYTHON) scripts/build_hls.py --bambu "$(BAMBU)"

hls-contract: hls
	$(PYTHON) scripts/check_hls_contract.py

hls-check: hls-contract firmware
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) --hls && $(PYTHON) scripts/run_core.py $(core) --hls && $(PYTHON) scripts/build_core.py $(core) --hls --source sim/matrix_probe.cpp --output matrix_probe &&) true
	$(PYTHON) scripts/check_matrix.py --hls --out build/hls-matrix-regression
	$(PYTHON) scripts/check_vcs_failures.py --hls --out build/hls-negative

hls-workload-check: hls firmware llama
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) --hls --source sim/workload_probe.cpp --output workload_probe --link-ggml &&) true
	$(PYTHON) scripts/check_workload.py --model $(MODEL)

# Generated HLS output must exist; this target does not run an HLS compiler on macOS.
hls-lint:
	$(PYTHON) scripts/build_core.py ibex --hls --lint-only
	$(PYTHON) scripts/build_core.py cv32e40p --hls --lint-only
