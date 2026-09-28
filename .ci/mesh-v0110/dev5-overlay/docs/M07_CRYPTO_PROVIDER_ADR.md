# ADR — M07 crypto provider strategy

Status: CURRENT CANDIDATE / production security not yet claimed
Date: 2026-09-28

## Decision

Mesh Messenger keeps M07 as the stable provider boundary. Do not bind M02/M12/transports directly to a specific crypto library.

### Direct 1:1

Target security semantics remain:
- asynchronous first message;
- identity-authenticated session bootstrap;
- per-message key evolution;
- forward secrecy and post-compromise recovery;
- bounded skipped-message keys;
- replay rejection;
- deterministic cross-client interoperability vectors;
- future hybrid/PQ upgrade without changing M02/M12.

Current decision: do NOT make libsignal a hard production dependency yet.

Reason:
- libsignal is strong and implements the Signal protocol family;
- its own README states that use outside Signal is unsupported and APIs/bridge layers may change without notice;
- this makes it a poor long-lived ABI contract for Mesh Messenger even before licensing/product-policy review.

M07 must therefore remain provider-portable. A direct-ratchet implementation must pass the full M07 compatibility suite before selection.

### Private groups

Primary candidate: IETF MLS via OpenMLS.

Reason:
- RFC 9420 defines asynchronous group key establishment with forward secrecy and post-compromise security;
- the protocol is designed for groups from two to thousands;
- it fits Mesh Messenger private-group membership semantics better than pairwise fanout as a permanent architecture;
- pairwise fanout remains a compatibility/bootstrap implementation only until MLS interop/HIL is proven.

OpenMLS adoption is conditional on our own Android/JNI/FFI, persistence, crash-recovery and cross-language interoperability tests.

## Metadata boundary

Transport-visible M07 wire MUST NOT expose:
- sender MM-ID;
- recipient MM-ID;
- session ID;
- conversation ID/key;
- group ID;
- logical message ID.

The transport/relay sees only:
- M07 wire format version;
- crypto suite/version identifier;
- opaque provider ciphertext;
- transport-local opaque routing/capability metadata.

Application/session binding is authenticated inside provider ciphertext and validated against trusted receive context.

## Provider interface requirements

A production provider MUST implement:
1. local identity public material;
2. signed asynchronous bootstrap/prekey material where used;
3. session/group state creation;
4. encrypt exactly once per logical recipient message;
5. decrypt with expected sender/recipient/message context;
6. durable atomic state persistence before ciphertext is exposed to transport;
7. safe restart after crash between state mutation and send;
8. replay rejection;
9. bounded skipped-key storage;
10. key deletion/rotation rules;
11. versioned suite negotiation with downgrade rejection;
12. deterministic Flutter/Kotlin golden vectors;
13. Android hardware-backed key integration where algorithm/provider permits;
14. no plaintext or long-lived private material in logs/diagnostics/backups.

## Release gates

DIRECT_PROVIDER_SELECTED_PASS
DIRECT_ASYNC_FIRST_MESSAGE_PASS
DIRECT_RATCHET_PFS_PASS
DIRECT_POST_COMPROMISE_RECOVERY_PASS
DIRECT_REPLAY_REJECT_PASS
DIRECT_CRASH_ATOMICITY_PASS
DIRECT_SKIPPED_KEY_BOUND_PASS
M07_WIRE_METADATA_MINIMIZATION_PASS
PRIVATE_GROUP_MLS_INTEROP_PASS
FLUTTER_KOTLIN_CRYPTO_ENVELOPE_INTEROP_PASS
ANDROID_PROVIDER_HIL_PASS
RELAY_SEES_NO_APPLICATION_IDENTITY_PASS

## Current implementation status

Branch: security/m07-private-pipeline
PR: #7
M07 provider-portable wiring: implemented.
Release fail-closed private plaintext policy: implemented.
ContactCard v2 identity/prekey bootstrap shape: implemented.
Metadata-minimized M07 wire: implemented, CI verification pending/current.
Real production direct provider: not yet selected.
Real MLS/OpenMLS provider: not yet integrated.
Production E2EE claim: BLOCKED.
