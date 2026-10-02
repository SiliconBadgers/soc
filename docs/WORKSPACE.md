# Pinned component workflow

The SoC superproject owns device composition and records exact component
commits as Git submodules under `components/`. It also records upstream CPU,
llama.cpp and model revisions in `dependencies.json`. Model weights, licensed
libraries and generated build outputs stay outside Git.

## Get the same system

```sh
git clone --recurse-submodules https://github.com/SiliconBadgers/soc.git
cd soc
./scripts/workspace.sh verify
./scripts/workspace.sh test
```

For an existing clone, use `./scripts/workspace.sh init`. Initialization refuses
dirty component checkouts before updating clean checkouts to recorded commits.
`status` shows Git's revision markers; `verify` fails on missing modules, changed
commits, conflicts or local component edits. It never fetches branch tips for a
test. Initialization needs network access; the standalone RTL test does not need
CPU sources or model weights after the component checkout is initialized.

## Develop a component

Submodules start detached at the recorded commit. Create a branch inside the
owning component before editing:

```sh
cd components/rtl
git switch -c feat/controller-change
# Edit and run the component's checks.
git add rtl/
git commit -m "Describe the controller change"
git push -u origin feat/controller-change
```

Open the component PR first. Integration tests require clean component commits.
To test a proposed combination, stage the changed gitlinks in a SoC
branch, then run the workspace checks. Pushing the SoC commit does not
push a component commit; publish every referenced commit in its owning repo.

## Review a component update

In a SoC branch, fetch the owning component and explicitly check out
the reviewed commit. Replace REVIEWED_COMMIT with a real published SHA:

```sh
git -C components/rtl fetch origin
git -C components/rtl checkout --detach REVIEWED_COMMIT
git add components/rtl
./scripts/workspace.sh verify
./scripts/workspace.sh test
git diff --cached --submodule=log
```

Run the CPU, memory-service and software checks when the changed boundary affects
them. Record commands, component revisions, outcomes and limits in a new dated
experiment. Commit the gitlink update and open the SoC PR. Do not use
`git submodule update --remote` for reproduction: it replaces recorded revisions
with moving branch tips.

## Ownership and repository transition

Hardware composition lives here: core wrappers,
platform/host adapters, clocks/reset and connections to component blocks.
Compute, control and memory internals live in the combined `rtl` repository.
Architecture owns shared behavioral specifications; the provisional block command
package lives in `rtl/rtl/common/`. SoC owns device composition and CPU wrappers. Tests
and software probes are consumed from their owning submodules without copying.
Physical Design may have target-specific wrappers but should consume the same
component revisions instead of maintaining another authoritative RTL top.

The former Accelerator repository is not a dependency of this system. The migration does not introduce another
team or settle the open CPU, command ABI or compute partition decisions.
