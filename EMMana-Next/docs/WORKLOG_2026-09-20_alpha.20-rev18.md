# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev18
Date: 2026-09-20

## Scope
Add the first usable graphical antenna geometry editor without introducing a second model representation.

## Implemented
- Geometry workspace tab.
- Canvas wire editor in XY, XZ and YZ projections.
- Wire selection and endpoint drag.
- Start/End XYZ inspector.
- Diameter and segments editing.
- Add wire.
- Delete wire with optimizer-reference safety gate.
- Assign the single supported feed to the selected wire center segment.
- Model-check shortcut.
- Help topic.
- Dedicated geometry structure regression test.

## Data rule
The editor reads and writes the same EMNX wires[] and feeds[] shown in the JSON editor. There is no hidden geometry document, cache, or product-side duplicate.

## Drag rule
Only axes visible in the active 2D projection change during pointer drag. The third coordinate is preserved.

## Explicitly deferred
- 3D editor / WebGL.
- multi-feed/multiport interaction.
- graphical loads editor.
- design-variable/constraint graphical editing.

## Promotion
Promote rev18 only after JavaScript syntax, geometry gate, Linux UI smoke, full internal CTest, real NEC2, Windows x64 and source snapshot all pass.
