# AI/CV Modules

Shared contracts for reusable tracking / computer-vision modules.

Rules:
- experiments stay in the consuming project;
- only CANDIDATE/VERIFIED modules are promoted here;
- platform adapters do not own tracking logic;
- every state transition must expose a reason;
- every module must be replay-testable without Android UI;
- no YOLO dependency is required by these contracts.

Current incubator: Real-0.
