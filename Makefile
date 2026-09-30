PYTHON ?= python3
ZIG ?= zig
CMAKE ?= cmake
VERILATOR ?= verilator
CORES := ibex cv32e40p
RTL := rtl/integration/command_pkg.sv rtl/integration/engine_stub.sv components/rtl-control/rtl/integration/command_router.sv rtl/integration/command_router_test_top.sv
MODEL := .deps/models/Qwen3.5-2B-Q4_K_M.gguf

.PHONY: test deps model firmware cores llama graph-check model-check sweep

test:
	mkdir -p build/skeleton
	$(VERILATOR) --binary --timescale 1ns/1ps --timing --assert --top-module command_router_tb --Mdir build/skeleton $(RTL) components/verification/tb/integration/command_router_tb.sv
	build/skeleton/Vcommand_router_tb

deps:
	$(PYTHON) scripts/fetch_dependencies.py

model:
	$(PYTHON) scripts/fetch_dependencies.py --model

firmware:
	mkdir -p build
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/build/zig-cache $(ZIG) cc -target riscv32-freestanding -mcpu=generic_rv32+m -mabi=ilp32 -nostdlib -ffreestanding -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -O2 -Wl,-T,components/software/integration/firmware/link.ld components/software/integration/firmware/start.S components/software/integration/firmware/probe.c -o build/firmware.elf
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/build/zig-cache $(ZIG) objcopy -O binary build/firmware.elf build/firmware.bin

cores: firmware
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) && build/$(core)/core_probe build/firmware.bin &&) true

llama:
	$(CMAKE) -S .deps/llama.cpp -B build/llama -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DGGML_METAL=OFF -DGGML_BLAS=OFF -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF
	$(CMAKE) --build build/llama --target llama ggml -j4

graph-check: firmware llama
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) --source components/software/integration/llama_probe.cpp --output llama_probe --link-ggml && build/$(core)/llama_probe build/firmware.bin &&) true

model-check: graph-check
	$(foreach core,$(CORES),build/$(core)/llama_probe build/firmware.bin $(MODEL) &&) true

sweep: cores
	$(PYTHON) scripts/sweep.py --output build/control-sweep.json

.PHONY: doctor mac-test
doctor:
	$(PYTHON) workspace.py doctor
mac-test:
	$(PYTHON) workspace.py test

.PHONY: style format
style:
	python3 scripts/check_style.py

format:
	python3 scripts/check_style.py --fix

.PHONY: lint
lint:
	$(PYTHON) scripts/build_core.py ibex --lint-only
	$(PYTHON) scripts/build_core.py cv32e40p --lint-only
