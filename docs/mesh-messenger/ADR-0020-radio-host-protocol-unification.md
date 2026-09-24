# ADR-0020 — Unify external-radio host protocol on MM-UART/1

Status: ACCEPTED
Date: 2026-09-24

## Context

Main uses M03/MM-UART/1. Flutter uses the working EP2 LINK ASCII path and CRSF detection. Shared domain models alone do not guarantee radio interoperability when host protocols differ.

## Decision

Use MM-UART/1 as the canonical future application-to-radio host protocol.

Keep EP2 LINK ASCII as a temporary compatibility/hardware-bring-up adapter until custom firmware implements MM-UART/1 and passes physical HIL. Keep CRSF for stock ELRS detection/diagnostics.

## Consequences

- Main and Flutter stay different applications.
- Each may implement the host adapter independently.
- GET_CAPS, not radio chip names, defines features.
- New radio families do not create new app-domain models.
- Migration does not block current EP2 hardware testing.

## Verification

Required:
- shared JS/Dart frame vectors;
- malformed-frame and CRC rejection;
- capability fixture parity;
- physical MM-UART handshake;
- Main <-> Flutter delivery through compatible radio nodes.
