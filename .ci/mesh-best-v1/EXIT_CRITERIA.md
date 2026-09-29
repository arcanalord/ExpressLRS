# Best v1 exit criteria

Greenfield work stops if any of these become true:

- it requires duplicating current Flutter behavior without reducing debt;
- it cannot reach real LR24 HIL quickly;
- it introduces a second owner for delivery/security/files/routing;
- it needs migration hacks more complex than cleaning the existing Flutter line;
- ordinary build is not simpler than current overlay build.

Greenfield work is promoted if:

1. clean checkout builds APK;
2. text LR24 HIL passes on two phones;
3. QR/contact/trust baseline passes;
4. M05 20 KB / 100 KB / reconnect / hash passes;
5. M07 boundaries are preserved;
6. current user-visible essentials are reproduced;
7. code ownership is materially clearer than current Flutter.

Decision principle:
Rewrite only what earns its keep. Reuse proven algorithms and tests; do not reuse structural debt.
