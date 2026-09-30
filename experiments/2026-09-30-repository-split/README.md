# Consolidated SoC workspace validation

The split sources compile and run with their recorded component revisions. The
standalone RTL test passes eight command cases; the original MAC integration
pipeline passes 261 golden vectors and 131,600 smoke checks. Both Ibex and
CV32E40P boot the migrated firmware and pass all 24 memory-service configurations.
Both migrated software probes pass the MLP comparison and Qwen3.5-2B prefill/decode
logit comparison. Qwen logit differences remain zero against their matched CPU
references. Tensor arithmetic still runs on the host.

The workspace guard rejects a dirty component and a checkout at the wrong
revision, then passes after restoration. Missing nested dependencies were also
rejected during initial setup and initialized recursively.

[manifest.json](manifest.json) records commands, revisions, source hashes,
firmware hash, dependencies and limits. [control-sweep.json](control-sweep.json),
[llama-results.json](llama-results.json) and [workspace-guards.json](workspace-guards.json)
contain the results. The llama.cpp libraries were reused from the previous
pinned build; both probes and both core models were rebuilt in the new layout.
This run does not claim a clean upstream-library build or hardware acceleration.

Follow [SETUP.md](../../SETUP.md) to reproduce. The original SoC-layout results
remain unchanged in the [September 29 experiment](../2026-09-29-control-integration/ORIGIN.md).
