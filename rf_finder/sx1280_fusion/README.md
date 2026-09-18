# RF Finder Fusion 3 — SX1280 node profiles

This directory contains the first hardware-facing layer for the A/B/T ranging line.

## Profiles

- **A / COORDINATOR** — Android-connected coordinator, may range T and B, forwards normalized F3 UART lines.
- **B / ANCHOR** — remote anchor, may range T, forwards result to A over the future control channel.
- **T / TARGET** — own cooperative target, normally acts as ranging slave.

The node identity/profile is independent from the physical SX1280 board. Board pin mapping is intentionally not hard-coded here.

## Current stage

Implemented:

- A/B/T identities and ranging addresses
- two ranging radio profiles
- host/air protocol contract
- coordinator state machine abstraction
- concrete SX1280 ranging backend
- low-level SX1280 driver ranging primitives
- Android parser + measurement store + WLS solver

Not implemented yet:

- board-specific target definition for the exact SX1280 modules
- B→A control/relay packet transport
- calibrated sigma model
- LOS/NLOS classifier
- automatic session/time synchronization over air

## First hardware test

Do not start with three nodes.

1. Flash A + T.
2. Use fixed known distance 1 m.
3. Collect >=100 raw and filtered range samples.
4. Repeat 2 m and 3 m.
5. Verify calibration and TX-power dependence.
6. Then add B and repeat B↔T.
7. Only after both links are stable enable A/B/T localization.

This isolates radio-ranging faults from map/solver faults.
