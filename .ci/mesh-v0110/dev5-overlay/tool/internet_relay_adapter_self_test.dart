import 'dart:io';
import 'dart:typed_data';

import '../lib/platform/internet_relay_adapter.dart';
import '../lib/platform/internet_relay_contract.dart';

final class _FakeRelayClient implements InternetRelayClient {
  final Map<String, Map<String, RelayInboundPacket>> queues = {};
  final Map<String, RelayTransportResult> byIdempotency = {};
  int sequence = 0;

  @override
  Future<Map<String, dynamic>> fetchCapabilities() async => {
        'protocol': 'MM-RELAY/1',
        'maxCiphertextBytes': 64 * 1024,
        'maxPendingPacketsPerMailbox': 128,
        'maxPendingCiphertextBytesPerMailbox': 4 * 1024 * 1024,
        'defaultTtlSeconds': 7 * 24 * 60 * 60,
        'maxTtlSeconds': 14 * 24 * 60 * 60,
      };

  @override
  Future<RelayTransportResult> enqueue(RelayOutboundEnvelope envelope) async {
    final existing = byIdempotency[envelope.idempotencyKey];
    if (existing != null) {
      return RelayTransportResult(
        evidence: RelayTransportEvidence.duplicate,
        relayPacketId: existing.relayPacketId,
      );
    }
    final packetId = 'rp-${++sequence}';
    final packet = RelayInboundPacket(
      relayPacketId: packetId,
      ciphertext: Uint8List.fromList(envelope.ciphertext),
      expiresAt: envelope.expiresAt,
    );
    queues
        .putIfAbsent(envelope.mailboxHandle, () => {})
        [packetId] = packet;
    final result = RelayTransportResult(
      evidence: RelayTransportEvidence.stored,
      relayPacketId: packetId,
    );
    byIdempotency[envelope.idempotencyKey] = result;
    return result;
  }

  @override
  Future<List<RelayInboundPacket>> pull({
    required String mailboxHandle,
    String? cursor,
    int limit = 32,
  }) async =>
      queues[mailboxHandle]?.values.take(limit).toList(growable: false) ??
      const <RelayInboundPacket>[];

  @override
  Future<void> ackDelete({
    required String mailboxHandle,
    required String relayPacketId,
  }) async {
    queues[mailboxHandle]?.remove(relayPacketId);
  }
}

void expectTrue(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final fake = _FakeRelayClient();
  final now = DateTime.utc(2026, 9, 28, 19, 30);
  final adapter = InternetRelayAdapter(client: fake, now: () => now);

  final caps = await adapter.refreshCapabilities();
  expectTrue(
    caps.protocol == InternetRelayCapabilities.supportedProtocol,
    'capabilities negotiation failed',
  );

  final cipher = Uint8List.fromList([0x91, 0x22, 0xe3, 0x04]);
  final first = await adapter.sendCiphertext(
    mailboxHandle: 'mbx-opaque-random-b',
    idempotencyKey: 'idem-random-route-attempt-1',
    ciphertext: cipher,
    ttl: const Duration(days: 7),
  );
  expectTrue(
    first.evidence == RelayTransportEvidence.stored,
    'relay did not store ciphertext',
  );
  expectTrue(
    !first.isRecipientDelivered,
    'relay stored incorrectly became recipient Delivered',
  );

  final duplicate = await adapter.sendCiphertext(
    mailboxHandle: 'mbx-opaque-random-b',
    idempotencyKey: 'idem-random-route-attempt-1',
    ciphertext: cipher,
    ttl: const Duration(days: 7),
  );
  expectTrue(
    duplicate.evidence == RelayTransportEvidence.duplicate &&
        duplicate.relayPacketId == first.relayPacketId,
    'idempotent retry created a second relay packet',
  );

  final pulled = await adapter.pull(mailboxHandle: 'mbx-opaque-random-b');
  expectTrue(
    pulled.length == 1 &&
        pulled.single.relayPacketId == first.relayPacketId &&
        pulled.single.ciphertext.length == cipher.length,
    'store-and-forward pull failed',
  );

  await adapter.acknowledgeTransportReceipt(
    mailboxHandle: 'mbx-opaque-random-b',
    relayPacketId: pulled.single.relayPacketId,
  );
  final afterAck = await adapter.pull(mailboxHandle: 'mbx-opaque-random-b');
  expectTrue(afterAck.isEmpty, 'pull ACK did not delete relay packet');

  var tooLargeRejected = false;
  try {
    await adapter.sendCiphertext(
      mailboxHandle: 'mbx-opaque-random-b',
      idempotencyKey: 'idem-too-large',
      ciphertext: Uint8List(64 * 1024 + 1),
      ttl: const Duration(days: 1),
    );
  } on StateError {
    tooLargeRejected = true;
  }
  expectTrue(tooLargeRejected, 'relay hard ciphertext limit was ignored');

  stdout.writeln('MESH_MESSENGER_INTERNET_RELAY_ADAPTER_PASS');
}
