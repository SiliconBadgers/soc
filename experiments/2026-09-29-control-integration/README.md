# Existing-core and software integration experiment

**Result:** both Ibex and CV32E40P boot the same firmware, route commands through
RTL stubs and return explicit errors. All 24 control-memory configurations pass.
Host CPU ggml and Qwen3.5-2B numerical checks also pass with both core models.
This is control-path evidence, not a working tensor accelerator.

## Recorded checks

| Check | Ibex | CV32E40P |
|---|---:|---:|
| Boot cycles, response latency 1 / grant period 1 | 36 | 38 |
| Command round-trip cycles, latency 1 / period 1 | 56 | 76 |
| Command round-trip cycles, latency 2 / period 2 | 112 | 132 |
| Command round-trip cycles, latency 4 / period 3 | 168 | 198 |
| Command round-trip cycles, latency 8 / period 3 | 252 | 342 |
| ggml MLP maximum absolute error against scalar reference | 2.56841e-8 | 2.56841e-8 |
| Qwen prefill/decode maximum absolute logit difference | 0 | 0 |
| Selected Qwen operation probes | 1,422 | 1,422 |
| Total simulated cycles for those Qwen probes | 79,632 | 108,072 |

A command round trip starts when the C++ host publishes the mailbox request and
ends when firmware publishes its result. It includes polling, register writes,
completion reads and acknowledgement. Boot counts exclude the eight reset
cycles. Each sweep run checks four unimplemented engine routes, an invalid
opcode and an unsupported ABI version. All six commands have the same latency
in these runs because their stub responses have the same timing.

The standalone RTL test checks eight commands across all routes, completion
backpressure, stable identity after input changes, new-work blocking during
quiesce, draining a held completion and reset of a pending error response.

## Software workload

The numerical ggml test is a deterministic F32 MLP with input width 16, hidden
width 24 and three input vectors. It submits five metadata commands, receives
`UNIMPLEMENTED`, executes the whole graph on CPU and compares 48 output values
to a scalar reference. Maximum permitted absolute error is `1e-5`.

The model check uses the pinned `Qwen3.5-2B-Q4_K_M.gguf` listed in
[dependencies.json](../../dependencies.json), matching the model artifact in the
[Software baseline](https://github.com/SiliconBadgers/software/tree/main/experiments/llama-cpp/2026-09-22).
The prompt is `The purpose of a hardware accelerator is`, seven tokens with
this tokenizer. Each run processes the prompt, greedily chooses a token and
processes that one token in a 256-token context. It compares every last-position
logit at both stages, with a maximum permitted difference of `1e-5` and explicit
nonfinite-value rejection.

Reference and instrumented runs both use the same llama.cpp observation points.
Only the latter sends metadata to simulated firmware. The callback runs after
host execution; it does not implement device dispatch or a production fallback
backend. Matrix probes use the matrix route, gated-delta-net probes use the
state route and other selected compute probes use the vector route. That
classification tests routing; it is not a finalized workload mapping.

## Interpretation

Ibex uses fewer cycles in this specific polling loop. Core selection still
requires realistic firmware and interrupt behavior, production bus integration,
area and timing evidence. The test's instruction/data services are independent,
with no cache, tensor traffic or SRAM-bank competition.

The 1,422 probes include 374 matrix operations and 36 gated-delta-net operations
across prefill and decode. Those counts identify useful integration boundaries;
they do not estimate arithmetic latency, bandwidth or hardware capacity. In
particular, the total probe cycles cannot be used to calculate tokens/second or
the value of a dedicated recurrence engine.

No FPGA synthesis, ASIC synthesis, timing, power, long-context inference or real
offload was performed. The state and memory blocks remain unimplemented.

## Reproduction and records

Follow [SETUP.md](../../SETUP.md). The recorded command is:

```sh
make test cores sweep model-check \
  ZIG="$PWD/.deps/python/ziglang/zig" \
  CMAKE="$PWD/.deps/python/cmake/data/bin/cmake"
```

- [manifest.json](manifest.json): pinned inputs, tool versions, source and
  firmware hashes, command and standalone test result.
- [control-sweep.json](control-sweep.json): every memory-service configuration,
  boot count, status, sequence and command count.
- [llama-results.json](llama-results.json): numerical checks, operation counts
  and simulated control cycles for both cores.

The [integration guide](../../docs/integration/README.md) describes what is real
RTL, what is modeled, and what each component still needs to supply.
