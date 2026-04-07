# Register Allocation Simulator

Simulates how `StackToRegisterMappingCogit` maps stack values to registers in the Pharo VM's JIT compiler. Focused on what happens at merge points.

## What it does

- Models a simplified abstract state with N machine registers
- Simulates state divergence when bytecode execution branches (ifTrue:ifFalse:)
- Compares two merge strategies:
  - **Flush-all**: Current Cogit behavior. Discard all register assignments at merge. 0% utilization after merge.
  - **Reconciliation**: Keep registers where both branches agree. Spill only conflicts. Typically 40-60% utilization survives.

## Usage

```smalltalk
sim := RaSimulator new.
sim availableRegisters: 4.
sim report.
```

Output:

```
=== Register Allocation Simulation ===
Available registers: 4

Branch A final state: [R0=val1, R1=val3, R2=val4, R3=empty] util=75.0%
Branch B final state: [R0=val1, R1=val5, R2=empty, R3=empty] util=50.0%

Avg utilization before merge: 62.5%
Utilization after merge (flush-all): 0.0%
Utilization after merge (reconciled): 25.0%

Spills with flush-all: 3
Spills with reconciliation: 1
```

The key number: reconciliation reduces spills because it keeps R0 (both branches agree on val1) instead of throwing it away.

## Installation

File in `RegAllocSim-Core.st` into a Pharo 13 image.

## Context

Part of my GSoC 2026 exploration for the Register Allocation project with Pharo Consortium. This simulator helped me understand the core algorithm that `StackToRegisterMappingCogit` implements and where the flush-all behavior loses optimization potential.

## Author

Apex Poudel - apexpoudel111@gmail.com
