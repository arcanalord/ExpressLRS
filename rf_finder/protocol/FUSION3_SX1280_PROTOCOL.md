# RF Finder Fusion 3 — SX1280 Host/Air Protocol v0.1

Status: development contract for `rf-finder-fusion3-test`.

## Architecture

Fusion 3 uses three own nodes:

- **A** — coordinator/anchor. Connected to Android over USB-UART when possible.
- **B** — remote anchor.
- **T** — own SX1280 target.

The radio network and the Android transport are separate layers.

1. **Air layer**: A/B/T coordinate control and SX1280 ranging slots.
2. **Host UART layer**: coordinator forwards normalized node state, bearing and range measurements to Android.

Android must not depend on a particular SX1280 board implementation. It consumes normalized measurements.

## Important constraint

SX1280 ranging mode is not treated as normal ExpressLRS traffic. The existing ExpressLRS SX1280 driver already exposes the SX1280 RANGING packet type and ranging IRQ definitions, but this RF Finder branch does not yet contain a ranging state machine. Fusion 3 therefore keeps ranging as a separate cooperative mode and will time-slice control traffic and ranging.

## UART framing

UTF-8/ASCII line protocol, LF terminated.

Prefix: `F3`

Protocol version: `1`

All integer timestamps are milliseconds in the node's current session clock unless otherwise specified.

### HELLO

```
F3,HELLO,1,<device_id>,<role>,<fw>,<session_id>,<caps>
```

Example:

```
F3,HELLO,1,A-001,COORDINATOR,0.1.0,S17,RANGING|RELAY|RSSI
```

Roles:

- `COORDINATOR`
- `ANCHOR`
- `TARGET`

### STATE

```
F3,STATE,<device_id>,<session_id>,<seq>,<timestamp>,<state>,<target_id>,<battery_mv>,<rssi_dbm>
```

States:

- `OFFLINE`
- `IDLE`
- `READY`
- `RANGING`
- `ERROR`

### RANGE

```
F3,RANGE,<session_id>,<seq>,<from>,<to>,<target_id>,<timestamp>,
   <raw_mm>,<range_mm>,<sigma_mm>,<quality_milli>,<rssi_dbm>,<tx_dbm>,
   <LOS|NLOS|UNKNOWN>,<calibration_id>,<flags>
```

Rules:

- `range_mm` is calibrated range.
- `raw_mm` is preserved for diagnostics.
- `sigma_mm` is mandatory in the normalized contract even if firmware initially uses a conservative default.
- `quality_milli` is 0..1000.
- Android maps this directly to `RFFusionMeasurements.range()`.
- An NLOS sample is kept in logs but receives a low/zero estimator weight.

### BEARING

Optional remote-bearing message:

```
F3,BEARING,<session_id>,<seq>,<from>,<target_id>,<timestamp>,
   <bearing_mdeg>,<sigma_mdeg>,<quality_milli>,<rssi_dbm>,<calibration_id>,<flags>
```

A/B may still obtain bearing locally from the Android compass + directional antenna. This message exists so a future anchor with its own heading sensor can report bearing without changing Fusion Core.

### ACK / ERR

```
F3,ACK,<command>,<seq>,<status>,<detail>
F3,ERR,<code>,<seq>,<detail>
```

## Android → coordinator commands

```
F3,C,HELLO,1
F3,C,SESSION,<session_id>,<target_id>
F3,C,RANGE,<from>,<to>,<count>
F3,C,CAL,<device_id>,<calibration_id>
F3,C,STOP
```

## Initial coordinator schedule

The exact RF timing remains configurable until measured on hardware.

Recommended state machine:

1. CONTROL — A exchanges node state/control packets.
2. ARM_RANGE — A tells participating pair which nodes become ranging master/slave.
3. RANGE_SLOT — both nodes switch to SX1280 ranging mode.
4. RESULT — ranging master obtains result.
5. REPORT — result returns to coordinator A.
6. CONTROL — nodes return to control mode.

For A↔T:
- A = ranging master
- T = ranging slave

For B↔T:
- B = ranging master
- T = ranging slave
- B reports normalized result to A

A↔B is optional and used to cross-check the known/map baseline.

## Session and sequence rules

- Every field session has a `session_id`.
- Changing target starts a new session or clears target measurements.
- Each originating node increments `seq`.
- Android rejects duplicate/old `session + device + type + seq`.
- Measurements older than the solver age gate are STALE and do not drive T.

## Calibration

Each range must identify the calibration profile:

```
calibration_id = <board-revision>/<unit-id>/<antenna>/<tx-power>/<profile-version>
```

The calibration layer provides:

- corrected range;
- conservative sigma;
- optional LOS/NLOS state;
- raw range retained for diagnostics.

## Air packet recommendation

The over-air control format should be compact binary, independent from the UART text format.

Suggested header:

```
magic:u8
version:u8
type:u8
session:u16
seq:u16
src:u8
dst:u8
target:u8
flags:u8
payload...
```

Control packet types:

- BEACON
- SESSION
- RANGE_ARM
- RANGE_REPORT
- STATE
- TIME_SYNC
- STOP

The SX1280 hardware packet CRC remains enabled where supported. Application sequence/session checks remain mandatory.

## First implementation gate

Before implementing full SX1280 ranging radio code:

1. Android parser must accept synthetic HELLO/STATE/RANGE lines.
2. RANGE must enter the same Measurement Store as simulator/manual range.
3. duplicate sequence must be rejected.
4. wrong target ID must be rejected.
5. WLS solver must consume the result without special SX1280 logic.
6. CI must test the parser and round-trip encode/decode.

Only after this gate do we add the SX1280 master/slave RF state machine.
