# Mesh Messenger — Radio Host Protocol CURRENT

Date: 2026-09-24
Status: ACCEPTED TARGET / TRANSITION IN PROGRESS

## Decision

Canonical future application-to-external-radio host protocol: **MM-UART/1**.

Compatibility paths remain:
- **EP2 LINK ASCII 115200** — legacy / hardware bring-up adapter for current EP2 LINK v0.2.0 firmware.
- **CRSF 420000** — stock ELRS detection/diagnostics, not the canonical Mesh Messenger host protocol.

Main and Flutter remain separate applications and separate implementations. They share the protocol contract, not source code.

## Why the protocols diverged

Main M03 was designed as a reusable multi-radio module and therefore uses a generic versioned capability-driven host protocol.

Flutter deliberately selected the already-working EP2 LINK v0.2.0 ASCII protocol to bring real SX1280/ESP8285 hardware online quickly. This was pragmatic for HIL, but not the desired final architecture.

## Comparison

EP2 LINK ASCII is human-readable, easy to debug and already works with current firmware, but it is EP2-specific, text-oriented and lacks generic GET_CAPS negotiation.

MM-UART/1 uses versioned binary frames, COBS + delimiter, sequence, payload length and CRC16. It exposes HELLO / GET_INFO / GET_CAPS / GET_STATE / GET_STATS / SEND and asynchronous READY / RX_PACKET / TX_ACCEPTED / TX_RESULT / LINK_STATS / RADIO_ERROR / DEVICE_RESET events. It scales better to SX1280, LR1121, LR2021 and future radios.

CRSF remains useful for identifying stock ELRS hardware; its RC/telemetry semantics are not a replacement for the messenger host contract.

## Migration

1. Keep current EP2 LINK adapter working for hardware bring-up.
2. Flutter dev.8 now includes a Dart MM-UART/1 compatibility codec and CI vector test, but does not activate it as the current radio transport yet.
3. Add MM-UART/1 mode to custom radio firmware, preferably dual-protocol during transition.
4. Main and Flutter then use separate implementations of the same MM-UART/1 contract.
5. Retire EP2 ASCII to compatibility-only after HIL.

Do not blindly transmit MM-UART binary probes to unknown stock ELRS UART. Auto-detection must remain bounded and safe.
