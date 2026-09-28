import '../core/m12_transport_router.dart';

final class InternetRelayCapabilities {
  const InternetRelayCapabilities({
    required this.protocol,
    required this.maxCiphertextBytes,
    required this.maxPendingPacketsPerMailbox,
    required this.maxPendingCiphertextBytesPerMailbox,
    required this.defaultTtlSeconds,
    required this.maxTtlSeconds,
  });

  static const supportedProtocol = 'MM-RELAY/1';

  final String protocol;
  final int maxCiphertextBytes;
  final int maxPendingPacketsPerMailbox;
  final int maxPendingCiphertextBytesPerMailbox;
  final int defaultTtlSeconds;
  final int maxTtlSeconds;

  factory InternetRelayCapabilities.fromJson(Map<String, dynamic> json) {
    final protocol = (json['protocol'] ?? json['wireProtocol']) as String?;
    if (protocol == null || protocol != supportedProtocol) {
      throw StateError('RELAY_UNSUPPORTED_PROTOCOL');
    }
    int requiredInt(String key) {
      final value = json[key];
      if (value is int && value > 0) return value;
      if (value is num && value > 0) return value.toInt();
      throw FormatException('RELAY_CAPABILITY_INVALID:$key');
    }

    return InternetRelayCapabilities(
      protocol: protocol,
      maxCiphertextBytes: requiredInt('maxCiphertextBytes'),
      maxPendingPacketsPerMailbox:
          requiredInt('maxPendingPacketsPerMailbox'),
      maxPendingCiphertextBytesPerMailbox:
          requiredInt('maxPendingCiphertextBytesPerMailbox'),
      defaultTtlSeconds: requiredInt('defaultTtlSeconds'),
      maxTtlSeconds: requiredInt('maxTtlSeconds'),
    );
  }

  TransportCapabilities asTransport({
    required bool available,
    required bool validatedInternet,
    required bool metered,
    int? estimatedRttMs,
  }) =>
      TransportCapabilities(
        transportId: 'internet-relay',
        transportClass: TransportClass.internetRelay,
        available: available,
        validatedInternet: validatedInternet,
        metered: metered,
        supportsText: true,
        supportsAttachments: true,
        supportsBinary: true,
        estimatedRttMs: estimatedRttMs,
      );

  void validateCiphertextLength(int bytes) {
    if (bytes < 0 || bytes > maxCiphertextBytes) {
      throw StateError('RELAY_ENVELOPE_TOO_LARGE');
    }
  }

  Duration clampTtl(Duration requested) {
    final seconds = requested.inSeconds;
    if (seconds <= 0) throw StateError('RELAY_TTL_INVALID');
    final max = maxTtlSeconds;
    return Duration(seconds: seconds > max ? max : seconds);
  }
}

enum RelayTransportEvidence { accepted, stored, duplicate, rejected }

final class RelayTransportResult {
  const RelayTransportResult({
    required this.evidence,
    this.relayPacketId,
    this.detail,
  });

  final RelayTransportEvidence evidence;
  final String? relayPacketId;
  final String? detail;

  // Relay acceptance is M12 transport evidence only.
  // M02 recipient application ACK remains the sole direct-message Delivered gate.
  bool get isRecipientDelivered => false;
}

bool relayMetadataLooksOpaque(Map<String, Object?> metadata) {
  const forbiddenKeys = <String>{
    'mmId',
    'fromMmId',
    'toMmId',
    'contactName',
    'conversationId',
    'logicalMessageId',
    'messageId',
    'plaintext',
  };
  return metadata.keys.every((key) => !forbiddenKeys.contains(key));
}
