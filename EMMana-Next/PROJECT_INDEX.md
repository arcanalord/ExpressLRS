# EMMana-Next — PROJECT INDEX

**Current version:** 0.1.0-alpha.20-rev6  
**Current Git branch:** `arcanalord/ExpressLRS:emmana-next-alpha20`  
**Current commit:** `ad417be8cfdd2e815575102f261b0ffcdaf6d5bc`  
**Project storage owner:** Dropbox `/FPV Club Research/07_Simulation_Testing/EMMana-Next`  
**Git/CI mirror:** GitHub `arcanalord/ExpressLRS`, branch `emmana-next-alpha20`  
**Updated:** 2026-09-20

## Current source

- GitHub working source: `EMMana-Next/` on `emmana-next-alpha20`
- Dropbox current snapshot target: `EMMana-Next-0.1.0-alpha.20-rev6-source-artifact.zip`
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
