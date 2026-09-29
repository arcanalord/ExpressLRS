# Mesh Messenger Best v1 — Greenfield Spike

Status: EXPERIMENTAL / NOT RELEASE / NOT A FIFTH PRODUCT

Purpose:
Build the cleanest possible Flutter implementation of the canonical Mesh Messenger model, without legacy overlay/build debt, and compare it against the current Flutter release line.

This branch does NOT replace the current Flutter client yet.
It earns replacement only by passing the same physical gates with less architectural debt.

## Non-negotiable rules

1. One logical message = one messageId.
2. M02 owns outbox/retry/dedupe/delivery.
3. M03 is transport-only and never owns app semantics.
4. M05 owns file chunking/resume/hash.
5. M07 owns identity/trust/crypto.
6. M12 owns route selection only.
7. SentToTransport != Delivered.
8. File N/N != Complete until final integrity verification passes.
9. Contact != Verified. User trust != device trust.
10. No second transport until LR24 text + reconnect + dedupe passes HIL.
11. No UI redesign before the core vertical slice passes.
12. No Rust/shared-core-first requirement.

## Phase 0 — clean project skeleton

Target:
- ordinary Flutter checkout/build;
- no base64 source ZIP;
- no overlay reconstruction;
- no generated second engine;
- explicit package/module boundaries;
- tests live beside the owner module.

## Phase 1 — minimal vertical slice

UI -> use case -> M02 -> M07 boundary -> M12 single-route -> PreparedTransportPacket -> M03 LR24

Acceptance:
- A->B and B->A text;
- same messageId across retry;
- reconnect;
- dedupe;
- recipient ACK -> Delivered;
- transport ACK cannot mark Delivered;
- two phones + two LR24 physical PASS.

## Phase 2 — contacts/trust

- Nearby != Contact
- QR import with editable display name
- Contact != Verified
- new device is not silently trusted

## Phase 3 — M05

- 10–20 KB
- ~100 KB
- 3/3 and 4/4 finalization
- reconnect/resume
- missing-only retry
- SHA-256 before Complete
- proactive receiver COMPLETE after final verified chunk, explicit sender COMPLETE as fallback

## Promotion rule

Best-v1 replaces current Flutter only if it:
- reproduces required UX;
- passes all current source/tests;
- passes PHONE + RADIO_HIL;
- passes M05 physical tests;
- has a simpler ordinary build;
- removes overlay/source-ZIP dependency;
- does not regress M07 security boundaries.

Until then current Flutter remains the release/test client.
