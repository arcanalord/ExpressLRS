# Alpha.20 ground validation — internal gates

Date: 2026-09-20

These are internal numerical/consistency gates only. They do **not** close the independent NEC2 blocker.

## Fixture

B02A is a 0.5 m center-fed horizontal wire dipole at z=0.25 m, radius 1 mm, 51 segments, 299.792458 MHz.

B02A is intentionally separate from the canonical manifest B02 quarter-wave monopole over PEC. The canonical B02 requires a wire endpoint connected to the ground plane and remains deferred until that endpoint/boundary semantics is implemented and validated.

## Local results

| Environment | Zin, ohm | Power balance | Efficiency | Ground loss |
|---|---:|---:|---:|---:|
| Free space | 84.7543 + j46.7281 | 8.11e-6 | 1.000000 | 0 |
| PEC image | 105.185 + j79.4226 | 6.92e-6 | 1.000000 | 0 |
| epsr=13, sigma=0.005 S/m | 102.235 + j74.6165 | 0 by closure accounting | 0.885209 | 3.66290e-4 W |

High-conductivity finite-ground limit vs PEC: `|delta Zin| = 1.32174e-8 ohm` in the local gate run.

## Permanent alpha.20 gates

- Project v0.4 parses ground properties.
- Ground parameters participate in model hash v4.
- PEC ground solution remains finite and power balance is < 1e-2.
- PEC has zero dissipative ground term.
- Finite ground changes input impedance relative to free space.
- Finite-ground efficiency stays in (0, 1].
- High-conductivity limit approaches PEC within 1e-4 ohm for B02A.
- Lower-half-space pattern samples are suppressed when ground is active.
- ResultSet v0.6 serializes environment and ground-loss provenance.
- NEC2 export maps PEC to GN 1 and finite ground to independent-reference GN 2.

## External gate still open

A real networked `nec2c` run is still required. The own finite-ground approximation and NEC2 Sommerfeld/Norton method are intentionally different, so acceptance tolerances must be based on measured comparison rather than invented in advance.
