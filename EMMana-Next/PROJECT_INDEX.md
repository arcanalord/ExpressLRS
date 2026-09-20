# EMMana-Next — PROJECT INDEX

**Current version:** 0.1.0-alpha.20-rev15  
**Current Git branch:** `arcanalord/ExpressLRS:emmana-next-alpha20`  
**Source provenance:** exact Git SHA is stored in the CI source-manifest sidecar; PROJECT_INDEX intentionally does not hard-code its own commit SHA.  
**Project storage owner:** Dropbox `/FPV Club Research/07_Simulation_Testing/EMMana-Next`  
**Git/CI mirror:** GitHub `arcanalord/ExpressLRS`, branch `emmana-next-alpha20`  
**Updated:** 2026-09-20

## Current source

- GitHub working source: `EMMana-Next/` on `emmana-next-alpha20`
- Dropbox current snapshot target: `EMMana-Next-0.1.0-alpha.20-rev15-source-artifact.zip`
- Older source bundles are history/evidence and are not current.

## Current architecture

- Core: C++ Wire-MoM experimental solver
- UI/API: `apps/linux_web`
- Shared UI support: `apps/shared/help` only; it is not a second UI owner.
- Transient UI surfaces have one owner: sidebar / Quick Help / Full Help are mutually exclusive.

## Verification status

- CORE_PASS: PASS
- LINUX_RUNTIME_PASS: PASS
- HELP_REGISTRY_PASS: PASS
- UI_SURFACE_STATE_PASS: PASS
- INDEPENDENT_NEC2_PASS: PASS for strict B01 gate
- B02/B04 NEC2 characterization: PASS within current provisional tolerances
- WINDOWS_BUILD_PASS: PASS
- WINDOWS_PASS: PENDING real clean-run on a Windows machine
- Independent finite-ground validation: MEASURED / NOT ACCEPTED — current approximation remains experimental
- Independent conductor-loss / RLC-load validation: PENDING
- Production-kernel convergence/policy closure: PENDING

## Independent NEC2 evidence

GitHub Actions run: 35506144695

- B01: dR = -1.207684 ohm, dX = -2.140942 ohm — PASS STRICT
- B02: dR = +0.289335 ohm, dX = -1.565283 ohm — PASS characterization
- B04: dR = +2.330789 ohm, dX = -4.610689 ohm — PASS characterization

## Windows evidence

GitHub Actions run: 35506144689 — PASS build/regression/package.

## Current release blockers

1. Replace/augment the current finite-ground approximation with a validated Sommerfeld/Norton-grade treatment.
2. Re-run the six-case finite-ground NEC2 matrix and adopt evidence-backed tolerances only after the model improves.
3. Real Windows clean-run verification.
4. Independent finite-conductivity and R/L/C load validation.
5. Production kernel convergence and acceptance policy.
6. Final graphical geometry/editor workflow.

## Next engineering step

Prefer external-reference depth before adding new solver features:
1. add finite-ground comparison case against NEC2 Sommerfeld/Norton;
2. add conductor-loss/load reference cases;
3. freeze evidence-backed tolerances;
4. only then move to multiport/N-port and graphical geometry editor.


## Finite-ground characterization — 2026-09-20

Real NEC2 run 35509245561 measured six finite-ground cases. The current complex-image approximation is not accepted as authoritative. Worst measured delta was G01 at h=0.10 m: dR=-30.163280 ohm, dX=+12.262247 ohm. See `benchmarks/FINITE_GROUND_NEC2_ALPHA20.json`.


## Product Domain layer — rev6

The product workflow is explicitly separated from the physical EMNX solver model.

Product Project → Design Model → Analysis Plan → Execution → Evidence Bundle → Measurement Set → Report/Release.

Current registry: `apps/shared/product/product-registry.json`  
Analysis-plan contract: `schemas/analysis-plan-0.1.schema.json`  
World-product review: `docs/research/WORLD_PRODUCT_PATTERNS_2026.md`  
Decision: `docs/adr/ADR-0022-product-domain-layer.md`


## Templates / materials / measurements — rev7

- Template registry: `apps/shared/product/template-registry.json`
- Implemented synthesis: half-wave dipole, PEC quarter-wave monopole, 3-element Yagi
- Materials/ground registry: `apps/shared/product/materials-registry.json`
- Measurement contract: `schemas/measurement-set-0.1.schema.json`
- Measurement example: `measurements/examples/B01_vna.measurement.json`
- ADR: `docs/adr/ADR-0023-template-material-measurement-sidecars.md`

Template synthesis is Product Domain logic and returns a pure EMNX model. Raw measurements are sidecar assets and never overwrite simulated data.


## Rev7 gate note

Rev7 candidate was not promoted: Linux UI smoke exposed legacy seed schema 0.1 in synthesized output. Rev8 fixes this by normalizing synthesized template output to current EMNX schema 0.5 and model-checking the generated project.


## Measurement pipeline — rev9

- Touchstone S1P parser: `apps/shared/product/measurement.py`
- Supported S1P encodings: RI / MA / DB; frequency units Hz/kHz/MHz/GHz; reference resistance R.
- VNA CSV baseline parser: frequency + R/X columns.
- Derived normalized fields: S11 complex/magnitude/dB/phase, Z=R+jX, VSWR.
- Comparison engine: linear interpolation of measurement data to simulation sweep grid with delta R/X/VSWR/S11.
- Unsupported Touchstone parameter types and keywords fail explicitly.


## Rev9 gate note

Rev9 candidate was not promoted. The standalone measurement parser test passed, but Linux UI smoke encoded Touchstone newlines as literal backslash-n sequences. Rev10 corrects the test payload and adds HTTP error-body diagnostics; parser and solver behavior are unchanged.


## Measurement UI — rev11

- Real Linux web screen built from the approved Figma measurement comparison layout.
- Minimal workflow: import S1P/VNA CSV → run Sweep → compare → KPI/graph/table/provenance.
- Reuses existing rev10 measurement APIs; no solver or EMNX schema changes.
- Help topic: `emmana-next.measurement.compare`.
- Raw measurement remains a sidecar and never overwrites simulation.


## Rev12 UI hardening

Measurement provenance now HTML-escapes user-controlled file names and reference-plane text before rendering. No solver, EMNX, API contract or measurement math changes.


## Rev13 integration-gate fix

The measurement UI and rev12 provenance escaping are unchanged. The Linux integration smoke now uses an S1P fixture at 285/300/315 MHz so it overlaps the existing 285–315 MHz simulation sweep. Non-overlapping measurement/simulation ranges remain a hard API error.


## VNA CSV profiles — rev14

CSV import now auto-detects three simple schemas:
- Frequency + R/X
- Frequency + S11 Real/Imag
- Frequency + S11 dB/Phase

No vendor-specific adapter layer and no UI mode selector were added. Parsed measurements expose source_profile for provenance.


## Measurement correlation — rev9

Canonical normalized contract now uses `samples`, nested `source`, and `reference_impedance_ohm` only. Legacy parallel field names were removed from server/UI.

- Touchstone S1P: RI / MA / DB, Hz/kHz/MHz/GHz, reference R
- VNA CSV: S11 real/imag, S11 dB/phase, or R/X
- Comparison alignment: measurement interpolated onto simulation sweep frequencies within overlap
- Metrics: delta R, delta X, delta S11 dB, delta VSWR and resonance shift


## Rev15 — baseline reconciliation + immutable engineering artifacts

Rev15 reconciles the valid rev10–rev14 history with the later canonical measurement-contract commits. Git history is preserved; no force-reset is used.

- Canonical runtime measurement fields remain samples, nested source, and reference_impedance_ohm.
- Generic VNA CSV profile detection is preserved as source.profile, not restored as a parallel legacy field.
- DesignVariant v0.1 binds a named candidate to one exact EMNX model hash and immutable fingerprint.
- MeasurementSet v0.2 binds raw and normalized measurement SHA-256 values to exactly one DesignVariant/model hash.
- Engineering Report v0.1 binds simulation, measurement correlation and recorded evidence status without modifying solver trust.
- New API: /api/variant/create, /api/measurement/bind, /api/report/generate.
- Solver physics and EMNX schema are unchanged.
