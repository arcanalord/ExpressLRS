import 'dart:convert';
import 'dart:typed_data';

import '../domain/message.dart';

final class ProtectedEnvelope {
  ProtectedEnvelope({
    required this.messageId,
    required this.recipientMmId,
    required Uint8List protectedBytes,
    required this.cryptoVersion,
  }) : _protectedBytes = Uint8List.fromList(protectedBytes);

  final String messageId;
  final String recipientMmId;
  final Uint8List _protectedBytes;
  Uint8List get protectedBytes => Uint8List.fromList(_protectedBytes);
  final String cryptoVersion;
}

abstract interface class MessageProtector {
  ProtectedEnvelope protect(LogicalMessage message);
}

/// Test-only placeholder. Best v1 must fail promotion until a production M07
/// provider replaces this implementation.
final class DevelopmentMessageProtector implements MessageProtector {
  const DevelopmentMessageProtector();

  @override
  ProtectedEnvelope protect(LogicalMessage message) {
    final payload = utf8.encode(
      'best-v1-dev|${message.messageId}|${message.recipientMmId}|${message.text}',
    );
    return ProtectedEnvelope(
      messageId: message.messageId,
      recipientMmId: message.recipientMmId,
      protectedBytes: Uint8List.fromList(payload),
      cryptoVersion: 'DEV-NOT-PRODUCTION',
    );
  }
}
