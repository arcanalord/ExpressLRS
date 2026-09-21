# Mesh Wi-Fi 1.6 — Product Contract

Baseline: validated Mesh Messenger v1.5.9
Validated commit: fefe9c41213c4f23018648993fdf3f480de808b8
Figma: existing Mesh Messenger design system, screens 60–63 created for Mesh Wi-Fi 1.6

## Product rule

The user sees one contact and one chat.
Transport is an implementation detail and is selected automatically.

Preferred route order:
1. direct LAN / Wi-Fi when peers are locally reachable;
2. Internet relay when direct LAN is unavailable;
3. future transports may be added behind the same interface without duplicating contacts or chats.

The user must not manage WebRTC, IP addresses, ICE, relay rooms, or transport IDs in normal mode.

## Screens

### Chats
- fast list of contacts/conversations;
- search;
- compact secondary route state only when useful;
- examples: "Напрямую", "Интернет", "Авто".

### Conversation
- normal messenger UI;
- one identity per person;
- current route is secondary status;
- delivery state remains owned by Chat & Delivery;
- coordinates/messages open the existing map.

### Connection
- top-level state: "Всё работает" / degraded / offline;
- automatic route is the default;
- direct Wi-Fi LAN and Internet are shown as capabilities;
- engineering metrics are behind Diagnostics.

### Add contact
Pair once:
- scan QR;
- show own QR;
- enter short code.

The resulting trusted contact is reused across LAN and Internet.

## Map

Do not rewrite the map.
Keep validated v1.5.9 behavior:
- OSM display;
- phone GPS;
- one-finger pan;
- pinch zoom;
- +/- zoom;
- fit all points;
- current offline fallback.

Only connect contact/message actions to the existing map.

## Architecture

Chat / Map / Files
       |
Delivery layer
       |
Transport selector
   /         \
LAN          Internet
WebRTC       Relay

Transport selector is not allowed to create separate chats or identities.

## v1.6 scope

Required:
- installable Android APK;
- pair two devices;
- text A<->B;
- same LAN direct communication;
- different-city Internet communication;
- automatic route selection;
- queue while temporarily offline;
- delivery acknowledgement;
- location message opens existing map;
- reconnect without duplicate delivery;
- Help pattern on connection/pairing states.

Not required for first v1.6:
- live voice;
- video;
- Meshtastic integration in this Wi-Fi-focused APK;
- advanced QoS;
- public anonymous relay;
- major map redesign.

## Release gates

- baseline map regression PASS;
- startup/navigation smoke PASS;
- LAN two-device PASS;
- Internet two-unrelated-networks PASS;
- reconnect PASS;
- queue + ACK PASS;
- no duplicate delivery PASS;
- Android build PASS;
- APK verify PASS;
- phone runtime PASS.

Do not promote a release while any required gate is unverified.
