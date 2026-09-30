# Getting started

Initialize the recorded component checkouts with `./scripts/workspace.sh init`,
then follow [SETUP.md](../SETUP.md) for RTL/CPU/software tests. The
[submodule workflow](WORKSPACE.md) explains how to propose component changes and
update the system configuration.

`./scripts/workspace.sh mac-test` runs the original small MAC pipeline through
the Architecture contract, Software vectors, Compute RTL and Verification
checker. Its result applies to that example, not the complete accelerator.
