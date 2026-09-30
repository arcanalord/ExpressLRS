import 'dart:io';

import '../lib/platform/transparent_uart_radio_transport.dart';

void main() {
  var now = DateTime.utc(2026, 9, 30, 10);
  final peers = Lr24PeerReachability(
    freshFor: const Duration(seconds: 30),
    now: () => now,
  );

  if (peers.hasFreshPeers || peers.isFresh('mm:b')) {
    throw StateError('Empty reachability must start stale');
  }

  peers.markSeen('mm:b');
  if (!peers.hasFreshPeers ||
      !peers.isFresh('mm:b') ||
      !peers.freshPeerMmIds.contains('mm:b')) {
    throw StateError('Fresh peer was not recorded');
  }

  now = now.add(const Duration(seconds: 31));
  if (peers.hasFreshPeers || peers.isFresh('mm:b')) {
    throw StateError('Stale peer remained reachable after TTL');
  }

  peers.markSeen('mm:b');
  peers.clear();
  if (peers.hasFreshPeers || peers.isFresh('mm:b')) {
    throw StateError('Disconnect did not clear peer reachability');
  }

  stdout.writeln('MESH_MESSENGER_LR24_PEER_FRESHNESS_PASS');
}
