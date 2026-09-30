# Verilator compatibility waivers

`vendor.vlt` applies only to the upstream sources pinned in `dependencies.json`.
Project-authored RTL has no warning waivers. Missing pins and other enabled
Verilator warnings remain fatal. The configuration was exercised with Verilator
5.050; review it when changing either the core revision or the tool version.

| Warning | Scope and reason |
|---|---|
| `UNOPTFLAT` | Listed Ibex/CV32E40P internal control paths require Verilator's combinational settling. Waiving the warning allows simulation; it does not establish physical timing or freedom from combinational loops. |
| `WIDTHEXPAND`, `WIDTHTRUNC` | Listed CV32E40P lines use implicit extension, truncation, or vector conditions. Preserve upstream behavior for this integration experiment. These waivers do not prove arithmetic correctness for every instruction/configuration. |
| `CASEINCOMPLETE` | Listed CV32E40P decoding/control cases omit some encodings. Preserve the pinned implementation; the control-path tests do not exhaust illegal/internal states. |
| `COMBDLY` | The upstream behavioral clock-gate model uses a nonblocking assignment in `always_latch`. This model is for simulation and must be replaced by an appropriate technology primitive for FPGA or ASIC implementation. |

CV32E40P waivers name individual source lines. Ibex waivers match the reported
signals in individual source files. No waiver applies to an entire dependency
tree or changes the global fatal-warning policy. The remaining upstream risks
must be reviewed as part of core selection and hardware implementation.
