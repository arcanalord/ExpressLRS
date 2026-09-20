# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev4
Date: 2026-09-20

## Scope
Recovered stalled GitHub work, closed the real NEC2 CI failure, then removed transient UI surface stacking risk without changing the RF solver.

## Completed
- Located project in `arcanalord/ExpressLRS`, branch `emmana-next-alpha20`.
- Fixed NEC2 exporter comment-card placement: CM WIRE cards now precede CE.
- Added regression coverage preventing CM cards inside geometry/control section.
- Real nec2c cross-solver suite now PASS.
- Windows MSVC x64 build/regression/package PASS.
- Found UI ownership overlap: sidebar and Help independently mutated body scroll lock and hidden state.
- Replaced it with one surface owner.
- Sidebar, Quick Help and Full Help are mutually exclusive.
- Added `emnext_ui_surface_state` regression test.
- Linux CTest now 10/10 PASS.

## Evidence
- NEC2 run 35506144695
- Windows run 35506144689
- rev4 UI commit ad417be8cfdd2e815575102f261b0ffcdaf6d5bc

## No layering rule
- One current version is declared only through PROJECT_INDEX.md.
- Older source/LATEST files are history until explicitly archived.
- No second UI owner was added.
- Solver/core was not modified by rev4 UI-state change.

## Next
1. Persist rev4 source/evidence to Dropbox.
2. Archive old root-level historical bundles after duplicate/evidence review.
3. Add finite-ground NEC2 reference case.
4. Add conductor-loss and RLC-load independent reference cases.
5. Run Windows package on a real Windows host.
