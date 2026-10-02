# SystemVerilog standards regression

The source revision and component pins are recorded in [results.json](results.json).
This regression checks the renamed interfaces, separated command router/fixtures,
explicit CPU connections, and strict warning policy.

| Check | Result |
|---|---|
| Verible formatting and default style rules | Seven integration sources pass |
| Ruff lint and formatting | Four integration build/check scripts pass |
| Verilator elaboration | Both cores pass with the documented upstream-only waivers |
| Directed routing simulation | Eight command cases pass |
| Firmware service sweep | All 24 core/latency/grant configurations pass |
| ggml MLP comparison | Maximum absolute error 2.56841e-8 on both cores |
| Qwen3.5-2B probe | 1,422 observed commands per core; zero final-logit difference |
| Negative checks | Missing CPU input rejected with PINMISSING; formatting drift rejected |

## Reproduce

Initialize the recorded component pins and dependencies using SETUP.md. Install
Verible v0.0-3946-g851d3ff4 and Ruff 0.16.6 for matching style results.

```sh
./scripts/workspace.sh verify
make style lint test
make cores ZIG="$PWD/.deps/python/ziglang/zig"
python3 scripts/sweep.py
python3 scripts/build_core.py ibex --source components/software/integration/llama_probe.cpp --output llama_probe --link-ggml
build/ibex/llama_probe build/firmware.bin .deps/models/Qwen3.5-2B-Q4_K_M.gguf
python3 scripts/build_core.py cv32e40p --source components/software/integration/llama_probe.cpp --output llama_probe --link-ggml
build/cv32e40p/llama_probe build/firmware.bin .deps/models/Qwen3.5-2B-Q4_K_M.gguf
```

The probe build requires the pinned llama.cpp libraries; follow SETUP.md to
build them. This run reused those libraries and rebuilt firmware, the Verilated
cores, and the C++ probes. The Qwen case uses seven prompt tokens and one decode
token. Tensor math remains on the host; these results do not validate accelerator
arithmetic or throughput. No synthesis, timing, CDC, four-state simulation, or
FPGA deployment was run. Existing dated experiment records are unchanged.

The negative checks temporarily removed `.instr_rvalid_i` from the CV32E40P
instance and changed indentation in `engine_stub.sv`, respectively. Each check
required a failing return code and its expected diagnostic; both files were
restored before the passing regression. Upstream waivers are documented in
[config/README.md](../../config/README.md).
