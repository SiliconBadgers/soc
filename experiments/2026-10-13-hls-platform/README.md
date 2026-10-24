# HLS platform validation

The HLS path replaces device-side C++ RAM, MMIO, descriptor access and matrix
memory callbacks with generated hardware and explicit RTL bus transactions.
Both existing RISC-V cores execute the unchanged command firmware against this
path. Adam Shebani's matrix-array sources are unchanged.

**All planned functional checks passed.** The final regression covers both CPU
configurations, 24 memory-service configurations, partial Qwen prefill/decode
co-execution and eight deliberately failing cases. All recorded compiled input
hashes match source revision `6c0099ebbb943fb5df213bc57bc65576aaca5afb` and its
pinned/generated dependencies. The [machine-readable results](results.json)
include per-run counts, elapsed times, simulator hashes and hashes of 37 raw logs.

## Results

| Check | Result | Scope |
|---|---|---|
| Bambu 2024.10 generation | Pass | RAM, register decoding, descriptor capture and bounded tensor access |
| Native C++ contract | 16,485 checks passed | Also passed Clang undefined-behavior checking |
| Generated RTL contract in VCS | 16,485 checks passed | Memory initialization, byte enables, register status, descriptor capture, errors, tensor bounds and control reset |
| Ibex and CV32E40P firmware probes | Pass | Six protocol/error commands and matching completions on each core |
| Matrix sweep | 24/24 configurations passed | Two cores × response-delay settings 1, 2, 4, 8 × grant periods 1, 2, 3 |
| Matrix arithmetic and command rejection | Pass in every configuration | Eight valid commands, 15 rejected commands and 401 exact output checks per run; 9,624 output checks in total |
| Reset and completion stalls | Pass in every configuration | One reset after active matrix traffic per run; completion backpressure observed |
| Partial Qwen co-execution | Pass on both cores | Actual model weights/activations, hardware results fed into prefill and decode |
| Deliberately failing checks | 8/8 detected; VCS exit code 3 | One corrupt HLS-contract result, two corrupt matrix results, two corrupt Qwen results, two empty-firmware cases and one unknown active host-interface signal |
| Authored SV/Python style | Pass | Verible and Ruff |
| Both SoC configurations, Verilator lint only | Pass | File-scoped waivers for generated-cell width conversions and unused `wenable` pins |
| Result-parser checks | Seven passed | Incomplete or failed output cannot satisfy the result parser |
| Code, functional and assertion coverage | Not measured | Directed pass counts are not coverage closure |
| Physical synthesis / PPA | Not run | No area, timing, power or FPGA-frequency claim |

The 16,485 contract checks include 16,384 initialization writes. The remaining
101 checks exercise the register, memory, descriptor and error contracts; the
headline count is not a count of distinct scenarios.

VCS reports six unconnected-port warnings per system build, all from Bambu's
input-register cells. Those cells declare but do not use `wenable`; the generated
code is retained unchanged. No authored RTL warning is suppressed by the HLS
lint configuration.

| Final matrix sweep | Ibex | CV32E40P |
|---|---:|---:|
| Configurations passed | 12 | 12 |
| Sum of command cycles per configuration, range | 40,989–79,683 | 41,709–81,123 |
| Simulation wall time per configuration, range | 26.483–43.635 s | 23.473–38.808 s |
| Simulation wall time across 12 configurations | 391.221 s | 347.504 s |

These are simulation counts for the conservative shared memory service and the
specified test traffic. Wall time measures verification runtime; neither metric
is a measured device frequency, application token latency or CPU-selection result.

## Qwen workload scope

The workload is the pinned Qwen3.5-2B Q4_K_M GGUF with the prompt
`The purpose of a hardware accelerator is`: seven prompt tokens, followed by
one generated token. The selected projection has a reduction dimension of
2,048. Eight output channels are replaced in each stage.

The host converts actual weights and activations to symmetric INT8, submits
8-wide reduction tiles through firmware, and reads INT32 values written by the
real array into HLS-generated RAM. After host accumulation and scaling, the
results replace the corresponding ggml outputs before subsequent operations
execute. The rest of the model runs on the host CPU. The hook also still lets
the CPU calculate the original projection before replacing the selected
outputs; it is not a production offload backend.

| Final Qwen check | Ibex | CV32E40P |
|---|---:|---:|
| Prompt / generated tokens | 7 / 1 | 7 / 1 |
| Hardware matrix commands | 512 | 512 |
| Exact integer outputs checked | 16,384 | 16,384 |
| Projection values replaced | 64 | 64 |
| Final logits compared | 496,640 | 496,640 |
| Maximum logit error versus equivalent scalar INT8 reference | 0 | 0 |
| Maximum logit difference versus original llama.cpp execution | 0.521974 | 0.521974 |
| Matrix memory reads / writes | 49,152 / 16,384 | 49,152 / 16,384 |
| Sum of command cycles | 2,322,414 | 2,368,494 |
| Simulation wall time | 9.378 s | 8.679 s |

Both runs select tensor `node_13`, with `K=2048`, `M=8` and `N=7` during prefill
or `N=1` during decode. The nonzero difference from original llama.cpp confirms
that inserted values affect inference. It is not an accuracy evaluation of the
INT8 conversion. Command cycles exclude host tensor loading, output reads,
quantization, scaling and the remaining model computation.

Vector and recurrent operations remain unsupported device commands. No
full-model hardware inference, long-context performance or quantization-quality
result is claimed.

## Revisions and reproduction

The change is based on SoC `ef6b75ae1d891b9b966c2cc073a3c73072a406d1` and retains
these component pins:

| Component | Revision |
|---|---|
| RTL | `564aa7b0fdb653277c726ca05f1edffa7339dd70` |
| Software | `8b159cba4df736796f5d7ed650bdb12082a13516` |
| Verification | `0ea25f1755e60b5105d5bc7170dd48b670b6a076` |
| Ibex | `4dd3932a36b5af5ac002bddbe16a1b4ead1a6fd8` |
| CV32E40P | `6033d2b1be3295ec774d17ac4cf226faacfdeb08` |
| llama.cpp | `19e28a27702117d8f2eb16b825b9a308111f67d9` |

HLS uses Bambu 2024.10, revision
`c2ba6936ca2ed63137095fea0b630a1c66e20e63-main`, with its Clang 16 frontend and
the exact arguments in `scripts/build_hls.py`. RTL simulation uses VCS
`Y-2026.03_Full64`. Tests are deterministic; no random seed is used.

See [the HLS guide](../../docs/HLS.md) for prerequisites and interface details.
From the repository root:

```sh
make hls-check BAMBU=/absolute/path/to/bambu-2024.10.AppImage
make hls-workload-check BAMBU=/absolute/path/to/bambu-2024.10.AppImage
make hls-lint
make style
python3 -m unittest discover -s scripts -p 'test_*.py'
```

The model is `Qwen3.5-2B-Q4_K_M.gguf`, SHA-256
`aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223`.
Firmware SHA-256 is
`621423c60a56788806c0309b6a5006eafac9d5b4f4bac27f71eb92a71570cac2`.
The HLS source, generated files, compiled inputs and simulator binaries have
individual hashes in [results.json](results.json).

`build/hls/platform/manifest.json` records the HLS generation inputs and outputs.
Each VCS `build.json` records the compiled RTL/C++ inputs and simulator hash;
`summary.json` records firmware/model hashes, results and elapsed time. The
published JSON extracts these records with portable paths. Raw licensed-tool
output and simulation databases are not committed.

The recorded system regressions used these output directories:

```sh
python3 scripts/check_matrix.py --hls --out build/hls-matrix-final
python3 scripts/check_workload.py --out build/hls-workload-final
python3 scripts/check_vcs_failures.py --hls --out build/hls-negative-final
```

Use a new output directory for another run. An interrupted matrix sweep can
continue with `--resume` and the same output directory. Completed runs are reused
only when their binary and firmware hashes and test settings match. Incomplete
output is retained separately.

```sh
python3 scripts/check_matrix.py --hls --resume --out build/hls-matrix-final
```
