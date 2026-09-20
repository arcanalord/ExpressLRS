# Known issues — 0.1.0-alpha.20-rev2

- Real independent NEC2 execution is still NOT RUN; fake NEC2 CTest covers adapter plumbing only.
- Own Wire-MoM remains Experimental; production kernel convergence/policy is not closed for all self/adjacent/source/end-cap cases.
- Finite ground uses a complex-image/quasistatic approximation and is not a Sommerfeld/Norton implementation.
- Ground-terminal feed is currently restricted to PEC ground until finite-ground terminal semantics are independently validated.
- Independent loss/load and finite-ground cross-solver validation remains open.
- Windows portable packaging and clean-Windows runtime verification are open.
- Linux Lab is a rapid verification UI, not the final M8 desktop geometry editor. Project editing still relies substantially on EMNX JSON.
- Live headless-Chromium navigation to container localhost is blocked by environment browser policy; live server/API smoke uses urllib, while visual browser checks use the real UI code with mocked transport and real solver result payloads.
