# RF Finder Fusion 3 — Development Worklog

## 2026-09-18 — Fusion 3.4

### Scope

Three own nodes:

- A — coordinator / anchor
- B — remote anchor
- T — own SX1280 target

### Implemented

- A/B/T map and local geometry
- normalized POSE / BEARING / RANGE Measurement Contract
- health states GOOD / SUSPECT / NLOS / STALE / REJECTED
- deterministic simulator/replay
- weighted ENU least-squares solver
- covariance + uncertainty ellipse
- robust Huber weighting
- UART host protocol v1
- protocol node registry with sequence de-duplication
- target ID gate
- F3 HELLO / STATE / RANGE / BEARING / ACK / ERR parsing
- Android UI buttons for HELLO / RANGE A-T / RANGE B-T / STOP
- firmware-side host protocol header
- platform-neutral cooperative ranging controller state machine
- SX1280 driver low-level ranging primitives
- CI self-tests for JS protocol round-trip, solver scenarios and C++ protocol/controller

### SX1280 low-level support added

- RANGING packet mode configuration
- ranging role Master / Slave
- device ranging address
- request ranging address
- calibration register
- ranging filter clear / sample count
- ranging result readout
- power-delta indicator
- master/slave start wrappers

### Verified constraints

Ranging mode is separate from normal ELRS traffic. Fusion 3 will time-slice control and ranging until field measurements justify another scheduler.

Ranging setup is restricted to SX1280-supported ranging LoRa parameters. Calibration remains explicit and must include the RF path and TX power.

### Current gate

1. CI latest branch head.
2. Cloud artifact snapshot containing APK + protocol + solver + driver source.
3. Android simulator regression.
4. Then board-specific SX1280 backend and real A-T / B-T hardware ranging.

### Known CI infrastructure issue

Several intermediate runs failed after successful code/firmware validation because Maven Central returned HTTP 429 while Gradle fetched Android dependencies. CI concurrency has been added to serialize future Fusion 3 runs and reduce duplicate dependency traffic.
