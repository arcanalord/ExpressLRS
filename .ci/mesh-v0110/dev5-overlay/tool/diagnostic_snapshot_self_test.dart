import 'dart:convert';
import 'dart:io';

import '../lib/core/diagnostic_snapshot.dart';

void main() {
  final snapshot = DiagnosticSnapshot.build(
    appVersion: '0.1.10-dev.15-channel-r2',
    ownMmId: 'mm:self',
    activeConversation: 'channel:general',
    transport: <String, dynamic>{
      'kind': 'LR24-F',
      'state': 'connected',
      'password': 'must-not-leak',
      'nested': <String, dynamic>{'privateKey': 'nope', 'rttMs': 42},
    },
    counters: <String, dynamic>{
      'txFrames': 10,
      'rxFrames': 9,
      'badFrames': 1,
    },
    extra: <String, dynamic>{
      'firmware': 'stock',
      'seedStorage': 'must-not-leak',
    },
  );
  final encoded = DiagnosticSnapshot.encode(snapshot);
  final decoded = jsonDecode(encoded) as Map<String, dynamic>;
  if (encoded.contains('must-not-leak') || encoded.contains('nope')) {
    throw StateError('Sensitive diagnostic field leaked');
  }
  if (decoded['schema'] != 'mesh-messenger-diagnostics/v1') {
    throw StateError('Diagnostic schema mismatch');
  }
  final transport = decoded['transport'] as Map<String, dynamic>;
  if (transport['kind'] != 'LR24-F' ||
      (transport['nested'] as Map<String, dynamic>)['rttMs'] != 42) {
    throw StateError('Safe diagnostics were lost');
  }
  stdout.writeln('MESH_MESSENGER_DIAGNOSTIC_SNAPSHOT_PASS');
}
