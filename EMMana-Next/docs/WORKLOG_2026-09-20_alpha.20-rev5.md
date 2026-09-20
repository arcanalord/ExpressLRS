# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev5
Date: 2026-09-20

## Goal
Close the finite-ground knowledge gap with a real independent NEC2 measurement matrix, without changing the RF model before measurement.

## Added measurement matrix
- G01 average ground, h=0.10 m
- G02 average ground, h=0.25 m
- G03 average ground, h=0.50 m
- G04 average ground, h=1.00 m
- G05 dry ground, h=0.25 m
- G06 wet ground, h=0.25 m

## Independent result
GitHub Actions NEC2 run 35509245561: execution PASS. This means the measurement pipeline ran correctly; it does NOT mean the finite-ground model is accepted.

Measured deltas (EMMana - NEC2), ohm:
- G01: dR -30.163280, dX +12.262247
- G02: dR +5.783069, dX +8.926480
- G03: dR -2.222567, dX -8.092339
- G04: dR -1.664813, dX -5.207546
- G05: dR +5.700115, dX +9.099150
- G06: dR +4.731362, dX +7.465247

## Decision
Do not create a permissive tolerance to make these cases PASS. Mark homogeneous-halfspace-image-v1 experimental/not-authoritative. The low-height G01 error demonstrates the current quasistatic complex-image approximation is not sufficient.

## User-facing protection
The solver now emits an explicit warning that real NEC2 characterization found non-negligible finite-ground impedance error and large low-height error.

## Next
Implement a validated Sommerfeld/Norton-grade finite-ground treatment (or an external-reference-backed equivalent) before promoting finite-ground results.
