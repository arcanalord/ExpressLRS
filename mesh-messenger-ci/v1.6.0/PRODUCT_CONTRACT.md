# Mesh Wi-Fi 1.6 — Product Contract

Baseline: validated Mesh Messenger v1.5.9

## Current phase — LAN only

The active Mesh Wi-Fi build must work without an Internet relay.

**One person = one contact = one chat.**

Current transport:
1. direct LAN / Wi-Fi only.

A contact is saved from valid identity material even when no LAN route exists. Contact existence, trust and route availability are independent states.

If the peer is unavailable, the message stays in the persistent local delivery queue. There is no hidden Internet fallback in the active build.

Internet relay remains a future transport in the shared architecture and is intentionally deferred.

## User experience

Normal flow:
- open Chats;
- add a contact;
- exchange QR/code;
- save the personal contact even while offline;
- open one chat;
- write immediately; if no route exists the message queues;
- when LAN appears, the same contact/chat resumes delivery.

The user must not see or configure:
- relay URL;
- Internet room;
- Internet invite/code;
- ICE details;
- transport IDs.

Engineering details live behind Diagnostics.

## Identity target

The LAN contact must be compatible with the shared identity target:

**one MM-ID → one contact → one chat.**

Future Internet and Meshtastic bindings attach to the same MM-ID. They must not create duplicate contacts.

## Map

Do not rewrite the validated v1.5.9 map.

Keep:
- OSM display;
- phone GPS;
- one-finger pan;
- pinch zoom;
- +/- zoom;
- fit all points;
- current offline fallback.

## Delivery

Preserve:
- stable first-class messageId;
- persistent queue across app restart;
- retry/reconnect;
- ACK;
- deduplication;
- no duplicate chat message after retry;
- future compatibility with the shared Delivery Manager and E2EE layer.

## Required current release gates

- baseline map regression PASS;
- startup/navigation smoke PASS;
- LAN transport smoke PASS;
- Android build PASS;
- APK verify PASS;
- two-device same-LAN PASS;
- reconnect PASS;
- queue + ACK PASS;
- duplicate-delivery protection PASS;
- offline contact save PASS;
- outbox restart persistence PASS;
- stable messageId / ACK correlation PASS;
- phone runtime PASS.

## Deferred gates

- Internet relay runtime;
- two-unrelated-networks Internet test;
- relay deployment;
- LAN→Internet automatic fallback;
- relay ciphertext-only verification.

Do not promote the LAN build while any current required gate is unverified.
