PYTHON ?= python3
ZIG ?= zig
CMAKE ?= cmake
VERILATOR ?= verilator
CORES := ibex cv32e40p
RTL := rtl/integration/sb_types_pkg.sv rtl/integration/sb_engine_stub.sv rtl/integration/sb_accelerator_top.sv
MODEL := .deps/models/Qwen3.5-2B-Q4_K_M.gguf

.PHONY: test deps model firmware cores llama graph-check model-check sweep

test:
	mkdir -p build/skeleton
	$(VERILATOR) --binary --timing --assert --top-module tb_skeleton --Mdir build/skeleton $(RTL) tests/tb_skeleton.sv
	build/skeleton/Vtb_skeleton

deps:
	$(PYTHON) scripts/fetch_dependencies.py

model:
	$(PYTHON) scripts/fetch_dependencies.py --model

firmware:
	mkdir -p build
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/build/zig-cache $(ZIG) cc -target riscv32-freestanding -mcpu=generic_rv32+m -mabi=ilp32 -nostdlib -ffreestanding -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -O2 -Wl,-T,firmware/link.ld firmware/start.S firmware/probe.c -o build/firmware.elf
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/build/zig-cache $(ZIG) objcopy -O binary build/firmware.elf build/firmware.bin

cores: firmware
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) && build/$(core)/core_probe build/firmware.bin &&) true

llama:
	$(CMAKE) -S .deps/llama.cpp -B build/llama -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DGGML_METAL=OFF -DGGML_BLAS=OFF -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF
	$(CMAKE) --build build/llama --target llama ggml -j4

graph-check: firmware llama
	$(foreach core,$(CORES),$(PYTHON) scripts/build_core.py $(core) --source sim/llama_probe.cpp --output llama_probe --link-ggml && build/$(core)/llama_probe build/firmware.bin &&) true

model-check: graph-check
	$(foreach core,$(CORES),build/$(core)/llama_probe build/firmware.bin $(MODEL) &&) true

sweep: cores
	$(PYTHON) scripts/sweep.py --output build/control-sweep.json
