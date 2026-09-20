# ADR-0021 — Ground model v1: explicit image boundary + homogeneous half-space approximation

Status: **Accepted for alpha.20 experimental validation**  
Date: 2026-09-20

## Decision

Alpha.20 adds ground as part of the physical project model instead of treating it as a UI-only option.

Supported environment models:

- `free-space` — legacy behavior.
- `pec-image-v1` — horizontal PEC plane with image-current boundary treatment.
- `homogeneous-halfspace-image-v1` — flat homogeneous lossy half-space represented by a complex image/reflection approximation.

The ground plane is horizontal at `z = plane_z_m`. Alpha.20 requires all modeled wire surfaces to remain above the plane; ground-connected wire endpoints are intentionally deferred.

## Physical identity

Project schema becomes v0.4 and model hash becomes `fnv1a64-emnext-model-v4`. Ground mode, plane height, relative permittivity, and conductivity participate in the physical hash.

## Finite-ground approximation

For finite ground, the complex relative permittivity follows the convention

`eps_c = eps_r - j * sigma / (omega * eps0)`.

The current alpha uses a constant complex image-strength approximation derived from `eps_c`. This is an engineering approximation for the first ground milestone. It is **not** the Sommerfeld/Norton solution and must not be presented as such.

The PEC mode is a stricter internal boundary-condition gate. The high-conductivity finite-ground limit is required to converge toward the PEC result.

## Far field and power

When ground is active, far-field integration is over the upper hemisphere. Lower-half-space pattern samples are suppressed.

Material wire/load loss remains directly integrated. In finite-ground alpha.20, the ground-loss term is inferred from accepted-power closure after upper-half-space radiation and material losses. This is provenance-visible and is not a direct volumetric ground-loss integral.

## Independent NEC2 reference

The own finite-ground solver remains an image approximation. NEC2 reference export therefore deliberately maps finite ground to `GN 2` (Sommerfeld/Norton) as a higher-fidelity independent reference, not as an identical implementation.

No strict NEC2 delta is frozen until a real external `nec2c` run exists. PEC maps to `GN 1`. Ground export is currently limited to a plane at `z=0`.

## Deferred

- Ground-connected quarter-wave monopole basis/endpoint treatment.
- Sommerfeld/Norton near-field kernel in the own solver.
- Layered ground, radial screens, arbitrary terrain, finite ground planes.
- Direct volumetric ground-loss integration.
- Strict real-NEC acceptance tolerance.
