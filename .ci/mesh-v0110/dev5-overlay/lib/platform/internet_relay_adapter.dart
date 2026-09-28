import 'dart:typed_data';

import 'internet_relay_contract.dart';

final class RelayOutboundEnvelope {
  const RelayOutboundEnvelope({
    required this.mailboxHandle,
    required this.idempotencyKey,
    required this.ciphertext,
    required this.expiresAt,
  });

  final String mailboxHandle;
  final String idempotencyKey;
  final Uint8List ciphertext;
  final DateTime expiresAt;

  void validate() {
    if (mailboxHandle.trim().isEmpty ||
        idempotencyKey.trim().isEmpty ||
        ciphertext.isEmpty) {
      throw StateError('RELAY_ENVELOPE_INVALID');
    }
    final metadata = <String, Object?>{
      'mailboxHandle': mailboxHandle,
      'idempotencyKey': idempotencyKey,
      'expiry': expiresAt.millisecondsSinceEpoch,
    };
    if (!relayMetadataLooksOpaque(metadata)) {
      throw StateError('RELAY_METADATA_NOT_OPAQUE');
    }
  }
}

final class RelayInboundPacket {
  const RelayInboundPacket({
    required this.relayPacketId,
    required this.ciphertext,
    required this.expiresAt,
  });

  final String relayPacketId;
  final Uint8List ciphertext;
  final DateTime expiresAt;
}

abstract interface class InternetRelayClient {
  Future<Map<String, dynamic>> fetchCapabilities();

  Future<RelayTransportResult> enqueue(RelayOutboundEnvelope envelope);

  Future<List<RelayInboundPacket>> pull({
    required String mailboxHandle,
    String? cursor,
    int limit = 32,
  });

  Future<void> ackDelete({
    required String mailboxHandle,
    required String relayPacketId,
  });
}

final class InternetRelayAdapter {
  InternetRelayAdapter({
    required InternetRelayClient client,
    DateTime Function()? now,
  })  : _client = client,
        _now = now ?? (() => DateTime.now().toUtc());

  final InternetRelayClient _client;
  final DateTime Function() _now;
  InternetRelayCapabilities? _capabilities;

  InternetRelayCapabilities? get capabilities => _capabilities;

  Future<InternetRelayCapabilities> refreshCapabilities() async {
    final parsed = InternetRelayCapabilities.fromJson(
      await _client.fetchCapabilities(),
    );
    _capabilities = parsed;
    return parsed;
  }

  Future<RelayTransportResult> sendCiphertext({
    required String mailboxHandle,
    required String idempotencyKey,
    required Uint8List ciphertext,
    required Duration ttl,
  }) async {
    final caps = _capabilities ?? await refreshCapabilities();
    caps.validateCiphertextLength(ciphertext.length);
    final effectiveTtl = caps.clampTtl(ttl);
    final envelope = RelayOutboundEnvelope(
      mailboxHandle: mailboxHandle,
      idempotencyKey: idempotencyKey,
      ciphertext: ciphertext,
      expiresAt: _now().add(effectiveTtl),
    );
    envelope.validate();
    return _client.enqueue(envelope);
  }

  Future<List<RelayInboundPacket>> pull({
    required String mailboxHandle,
    String? cursor,
    int limit = 32,
  }) async {
    if (mailboxHandle.trim().isEmpty) {
      throw StateError('RELAY_MAILBOX_INVALID');
    }
    if (limit < 1 || limit > 128) {
      throw RangeError.range(limit, 1, 128, 'limit');
    }
    final now = _now();
    final packets = await _client.pull(
      mailboxHandle: mailboxHandle,
      cursor: cursor,
      limit: limit,
    );
    return packets
        .where((packet) => packet.expiresAt.isAfter(now))
        .toList(growable: false);
  }

  Future<void> acknowledgeTransportReceipt({
    required String mailboxHandle,
    required String relayPacketId,
  }) {
    if (mailboxHandle.trim().isEmpty || relayPacketId.trim().isEmpty) {
      throw StateError('RELAY_ACK_DELETE_INVALID');
    }
    return _client.ackDelete(
      mailboxHandle: mailboxHandle,
      relayPacketId: relayPacketId,
    );
  }
}
