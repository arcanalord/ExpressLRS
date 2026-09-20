# WORKLOG — EMMana-Next 0.1.0-alpha.20-rev10
Date: 2026-09-20

## Trigger
Rev9 candidate failed Linux UI smoke before NEC2 reference execution. Standalone measurement pipeline test passed.

## Root cause
The smoke-test Touchstone payload contained literal backslash-n sequences rather than newline characters. The API correctly rejected the malformed single-line payload.

## Fix
- send actual newline characters in the API smoke fixture;
- include HTTP error response body in smoke-test failures;
- no parser changes;
- no solver changes;
- no EMNX changes.

## Promotion
Rev10 becomes current only after internal tests, real NEC2, Windows build/regression/package and source snapshot all pass.
