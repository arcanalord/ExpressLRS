# Best v1 architecture

Dependency direction:

UI
  -> Application use cases
    -> M02 Delivery
      -> M07 Protection / Trust
        -> M12 Route selection
          -> PreparedTransportPacket
            -> M03 Transport adapter
              -> M09 Android USB/serial

M05 is a delivery payload engine layered above M12/M03:
FileTransfer -> chunks -> protected payload -> M12 -> M03.
M03 fragmentation is independent from M05 chunk identity.

## Owners

M01 App Shell
- navigation only
- no retry/routing/security ownership

M02 Delivery
- logical messageId
- outbox
- retry
- dedupe
- recipient-level delivery state
- crash recovery

M03 Transport
- opaque bytes / prepared packets
- transport-local addressing
- availability
- write/read
- no MM-ID/trust/history/delivery

M05 Files
- manifest
- transferId
- logical chunks
- missing map
- resume
- final hash
- Complete only after integrity

M07 Identity / Trust / Crypto
- MM-ID
- Contact
- user/device trust
- crypto provider
- protected envelope

M09 Platform
- Android USB
- secure storage adapters
- filesystem/platform plumbing

M10 Build/Release
- clean checkout
- CI
- APK evidence
- PHONE/RADIO_HIL evidence

M12 Routing
- one route first
- later failover/racing
- cannot decrypt payload
- cannot mark Delivered

## Boundary objects

ProtectedEnvelope
PreparedTransportPacket
TransportInboundFrame
TransportSubmitResult
CapabilitySnapshot
RecipientDeliveryState
DeliveryAggregate
DeliveryGoal

## Deliberately excluded from first slice

- Internet relay
- racing routes
- Meshtastic
- advanced groups
- desktop/web
- voice/PTT
- large media
- Rust shared core
- simulator expansion without a concrete failing gate
