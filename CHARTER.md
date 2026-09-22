# SoC composition and system interfaces: team charter

## Purpose

Bring the accelerator’s hardware capabilities together into a coherent system. The team makes block composition, host visibility and chip-level behavior understandable, so that individually developed components can participate in a usable and explainable whole.

System composition exposes assumptions that may be invisible inside an individual block. The SoC team develops the hardware context in which compute, memory and control interact with software and platform boundaries. Its work includes system modeling, interface reasoning, integration design, investigation and RTL.

## Responsibilities

### Hardware composition

Own top-level hardware organization and connections among accelerator blocks. Explain which component supplies each capability and how their assumptions fit together.

### Host-visible behavior

Develop the host interface, register/address decoding, system interconnect and visibility of configuration, progress, results and errors in collaboration with architecture, control and software.

### System-wide signals and boundaries

Reason about clock and reset organization, interrupts and crossings where the selected design requires them. Make the boundary between chip-level logic and platform-specific wrappers explicit.

### Integration understanding

Maintain diagrams, assumptions, interface rationale and evidence from composed hardware. Investigate emergent behavior and support changes that keep the hardware system coherent.

## Boundaries and shared decisions

SoC owns hardware composition and host-facing access. rtl-control owns execution sequencing; rtl-compute and rtl-memory own their respective block internals. Platform-specific shells, pin constraints and transport adaptation remain part of SoC integration scope. Accelerator owns combined-system understanding, experiments and release context across hardware and software. Shared address, command and reset semantics are agreed with architecture and the affected consumers.

## Member autonomy

Members may study interface options, map block connections, investigate reset behavior, model a system boundary, explore observability or develop integration hardware. The team decides internal organization within agreed external behavior. Changes that affect software access, block interfaces or platform assumptions are collaborative decisions. The scaffold does not select a bus standard, address map or top-level implementation.

## Collaboration

| Partners | Shared concerns |
|---|---|
| RTL block teams | Exchange concrete interface expectations, reset assumptions and composition needs while preserving each block’s authoritative implementation. |
| architecture and software | Agree on what software can observe and control, and how system behavior is described consistently. |
| verification, physical-design and accelerator | Provide system context for independent assessment, target adaptation and combined demonstrations; use their feedback to refine integration assumptions. |

## Possible directions

Possible directions include comparing host interfaces, making a block diagram executable, investigating clock/reset relationships, analyzing error visibility, building a system model or integrating selected blocks. Members choose the scale and form of their contribution.

## What progress means

Progress is visible when composition is easier to understand, cross-block assumptions are explicit and hardware behavior can be observed and explained. A resolved interface ambiguity, a useful system diagram or an integration experiment can advance the charter alongside production RTL.

Leads help members interpret this purpose, find collaborators, access resources
and share what they learn. Members choose their questions and contributions.
Research, design reasoning, experiments, implementation, documentation and
teaching can all advance the charter; success is not measured by the number of
code changes or completed tickets.

The team can revise this charter as its understanding evolves. Changes to a
shared boundary or commitment are discussed with the teams affected by them.
The [objectives](OBJECTIVES.md) describe durable outcomes, and the
[repository structure](README.md#repository-structure) provides places to develop
work without specifying a mandatory project or sequence.
