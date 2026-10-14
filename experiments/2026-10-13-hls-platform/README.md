# HLS platform validation

The HLS path replaces device-side C++ RAM, MMIO, descriptor access and matrix
memory callbacks with generated hardware and explicit RTL bus transactions.
Both existing RISC-V cores execute the unchanged command firmware against this
path. Adam Shebani's matrix-array sources are unchanged.

**Validation status: the complete regression is not yet confirmed.** HLS
generation, the standalone VCS contract check, both CPU probes and both partial
Qwen co-execution probes passed. Only the first three configurations of the
final 24-configuration matrix sweep have confirmed results. The remaining
configurations and final system-level deliberately failing checks still need
their results collected and reviewed.

## Confirmed checks

| Check | Result | Scope |
|---|---|---|
| Bambu 2024.10 generation | Pass | RAM, register decoding, descriptor capture and bounded tensor access |
| Native C++ contract | 16,485 checks passed | Also passed Clang undefined-behavior checking |
| Generated RTL contract in VCS | 16,485 checks passed | Memory initialization, byte enables, register status, descriptor capture, errors, tensor bounds and control reset |
| Deliberately incorrect contract result | Correctly failed | VCS returned exit code 3 |
| Ibex firmware probe | Pass | Six commands and six matching completions |
| CV32E40P firmware probe | Pass | Six commands and six matching completions |
| Final matrix sweep | Partially confirmed | Ibex delay setting 1 with grant periods 1, 2 and 3 passed; the full sweep is pending |
| Partial Qwen hardware co-execution | Pass on both cores | Prefill and decode results compared with the equivalent scalar INT8 reference |
| Authored SV/Python style | Pass | Verible and Ruff |
| Both SoC configurations, Verilator lint only | Pass | Generated-cell width conversions and its unused `wenable` pins have file-scoped waivers |
| Result-parser checks | Seven passed | Incomplete or failed evidence cannot satisfy the result parser |
| Code, functional and assertion coverage | Not measured | Directed pass counts are not coverage closure |
| Physical synthesis / PPA | Not run | No area, timing, power or FPGA-frequency claim |

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

The initial Ibex co-execution run checked 512 matrix commands, 16,384 integer
outputs and 496,640 final logits across prefill and decode. It replaced 64
projection values, with zero final-logit difference from the scalar reference
using the same INT8 conversion. The maximum difference from original llama.cpp
execution was 0.521974. That difference confirms that the inserted values
affected inference; it is not an accuracy evaluation. Both core configurations
subsequently passed after the bus grants were registered.

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

`build/hls/platform/manifest.json` records the HLS source and generated-file
hashes. Each VCS `build.json` records the compiled RTL/C++ inputs and simulator
binary hash; `summary.json` records firmware/model hashes, results and elapsed
time. Raw tool outputs remain in their corresponding build directories.

An interrupted matrix sweep can continue with `--resume` and the same output
directory. Completed runs are reused only when their binary and firmware
hashes and test settings match. Incomplete output is retained separately.

```sh
python3 scripts/check_matrix.py --hls --resume --out build/hls-matrix-regression
```
