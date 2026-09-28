# Mesh Messenger — future network analysis and field tools

Status: architecture backlog / future work.
Source: field-tool concepts reviewed from the user-provided reference screen on 2026-09-28.

## Principle

These tools belong to Advanced mode and must be isolated from normal messaging UX.
They must reuse the same node identity, presence, map, transport telemetry, M05 QoS and diagnostic snapshot layers rather than creating separate incompatible data models.

No tool in this document is a release blocker for text chat or M05 file transfer unless explicitly promoted later.

## Planned tool set

### 1. Route trace — manual
Purpose: build and inspect a route by explicitly selecting relay nodes.

Architecture:
- RouteTraceRequest {source, destination, orderedRelayIds}
- RouteTraceResult {hops, perHopRtt, loss, timestamp, transport}
- never silently changes production routing;
- starts as diagnostic simulation/measurement only;
- later can be promoted to route pinning if the routing layer supports it safely.

UI:
Advanced mode -> Tools -> Route trace -> Manual.

### 2. Route trace — map
Purpose: select relay nodes directly on the map and visualize hop order.

Reuse:
- existing map/node-location layer;
- same RouteTraceRequest/RouteTraceResult model as manual trace.

UI requirements:
- numbered hop markers;
- per-hop quality overlay;
- route distance and estimated/observed RTT;
- clear distinction between measured route and hypothetical route.

### 3. Antenna coverage
Purpose: visualize estimated or measured coverage around a node/antenna.

Architecture:
- CoverageSample {position, rssi?, loss?, snr?, goodput?, timestamp, transport}
- CoverageDataset bound to node + radio profile + antenna metadata.
- separate measured and estimated layers; never present estimates as measurements.

Future inputs:
- device GPS/map position;
- RSSI/SNR when transport exposes them;
- loss/RTT/goodput fallback when RSSI is unavailable;
- optional antenna height/gain/orientation metadata.

### 4. Line of sight
Purpose: evaluate direct visibility between two selected map points/nodes.

Architecture:
- LineOfSightQuery {a, b, antennaHeightA?, antennaHeightB?}
- LineOfSightResult {distance, terrainProfile?, blocked?, clearance?, dataSource}

Important:
- initially a geometric/map tool;
- terrain/elevation data must be optional and source-tagged;
- do not infer guaranteed RF connectivity from geometric LOS alone.

### 5. RX journal
Purpose: real-time and persisted journal of received frames/events.

Architecture:
- RxJournalEntry {
    timestamp,
    transport,
    frameClass,
    sourceId?,
    destinationId?,
    channelId?,
    bytes,
    rssi?,
    snr?,
    crcOk?,
    duplicate?,
    hopCount?,
    messageId?
  }

Requirements:
- bounded ring buffer in normal runtime;
- optional persistent capture only in Advanced mode;
- export to diagnostic JSON/CSV later;
- privacy: payload content should be hidden by default; metadata-first logging.

### 6. Discover nearby nodes
Purpose: actively or passively enumerate recently reachable compatible nodes.

Reuse:
- existing presence/last-seen model;
- contact list remains separate from discovered nodes;
- discovery must never auto-trust or auto-add a contact.

NodeDiscoveryResult:
{mmId, displayName?, lastSeen, transport, rtt?, rssi?, loss?, hopCount?, location?}

UI:
- "Found nodes" list;
- actions: Add contact / Ping / Show on map / Diagnostics.

### 7. Region scan
Purpose: scan logical network regions/segments/channels when the transport supports that concept.

Architecture note:
"Region" is transport-specific and must not become a global identity primitive.

RegionDescriptor:
{id, label?, transport, capabilityFlags, metadata}

Examples:
- Meshtastic region/channel groups;
- logical Mesh Messenger channel/zone;
- radio-specific region profiles if later supported.

If a transport has no region concept, the tool must report unsupported rather than emulate one incorrectly.

### 8. Noise level monitor
Purpose: observe radio/channel noise and interference over time.

Architecture:
- NoiseSample {timestamp, transport, frequency?, noiseDbm?, rssiFloor?, packetErrorRate?, busyRatio?}
- NoiseMonitor produces rolling min/avg/max and event markers.

Capability fallback:
- if hardware exposes true RSSI/noise floor, show RF noise;
- otherwise show an explicit "link interference proxy" derived from loss/retries/RTT/goodput;
- proxy metrics must never be labeled as dBm noise.

Integration:
- feeds AdaptiveLinkPolicy;
- can suggest reliable/balanced/bulk M05 profile;
- must not automatically change RF hardware parameters unless both endpoints advertise safe profile-change capability.

## Shared diagnostic data model

All tools should emit source-tagged samples into a common telemetry bus:

TelemetrySample {
  timestamp,
  nodeId?,
  peerId?,
  transport,
  metric,
  value,
  unit,
  provenance,   // measured | derived | estimated
  confidence?,
}

This avoids separate incompatible counters for Chats, M05, Connection diagnostics and map tools.

## Advanced mode organization

Settings:
- Advanced mode toggle persists across restart.

Connection -> Advanced:
- active transport/profile;
- RTT, loss, goodput, retries;
- reconnect count;
- RX journal;
- noise/interference monitor;
- Test 100 / Test 1000;
- export diagnostics.

Map -> Advanced tools:
- Manual route trace;
- Map route trace;
- Antenna coverage;
- Line of sight;
- Nearby nodes;
- Region scan where supported.

## Suggested implementation order

Phase A — low risk / uses existing data:
1. RX journal.
2. Nearby nodes.
3. Advanced telemetry panel.
4. Noise/interference proxy from loss/RTT/retries/goodput.

Phase B — map integration:
5. Manual route trace.
6. Map route trace.
7. Line of sight.
8. Measured coverage samples.

Phase C — hardware/transport-aware:
9. True RF noise monitor where hardware supports it.
10. Region scan for transports that advertise the capability.
11. Coverage estimation with terrain/elevation sources.

## Non-goals for first implementation

- no automatic trust/contact creation from node discovery;
- no automatic route pinning from route trace;
- no automatic RF-rate switching without negotiated capability;
- no claim that LOS guarantees connectivity;
- no claim that derived interference metrics are true RF noise;
- no unbounded packet logging.

## Acceptance criteria before release of each tool

- feature capability-gated per transport;
- safe behavior when telemetry fields are unavailable;
- measured/derived/estimated provenance visible;
- no regression to text chat, General Chat, contacts or M05;
- widget regression tests for open/close/navigation;
- Android smoke test;
- physical two-device test when radio behavior is involved.
