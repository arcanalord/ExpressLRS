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

enum DevelopmentProtectedKind { text, recipientAck }

final class DevelopmentProtectedEvent {
  const DevelopmentProtectedEvent({
    required this.kind,
    required this.messageId,
    required this.senderMmId,
    required this.recipientMmId,
    this.text,
    this.ackedMessageId,
  });

  final DevelopmentProtectedKind kind;
  final String messageId;
  final String senderMmId;
  final String recipientMmId;
  final String? text;
  final String? ackedMessageId;
}

/// Test/HIL-only placeholder.
///
/// This is intentionally NOT production encryption. It exists only so the
/// greenfield Best-v1 branch can prove M02 -> M07 -> M12 -> M03 ownership,
/// physical LR24 routing, dedupe and recipient-ACK semantics before a real
/// crash-atomic production M07 provider is integrated.
final class DevelopmentMessageProtector implements MessageProtector {
  const DevelopmentMessageProtector({this.localMmId = 'mm:local'});

  final String localMmId;

  @override
  ProtectedEnvelope protect(LogicalMessage message) {
    return _encode(
      DevelopmentProtectedEvent(
        kind: DevelopmentProtectedKind.text,
        messageId: message.messageId,
        senderMmId: localMmId,
        recipientMmId: message.recipientMmId,
        text: message.text,
      ),
    );
  }

  ProtectedEnvelope protectRecipientAck({
    required String ackedMessageId,
    required String recipientMmId,
  }) {
    final ackEventId = 'ack:${localMmId}:${ackedMessageId}';
    return _encode(
      DevelopmentProtectedEvent(
        kind: DevelopmentProtectedKind.recipientAck,
        messageId: ackEventId,
        senderMmId: localMmId,
        recipientMmId: recipientMmId,
        ackedMessageId: ackedMessageId,
      ),
    );
  }

  DevelopmentProtectedEvent decode(Uint8List protectedBytes) {
    final decoded = jsonDecode(utf8.decode(protectedBytes));
    if (decoded is! Map) {
      throw const FormatException('BEST-V1 dev envelope is not an object');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['schema'] != 'mesh-best-v1-dev/v1') {
      throw const FormatException('BEST-V1 dev envelope schema');
    }
    final kindValue = '${map['kind'] ?? ''}';
    final kind = switch (kindValue) {
      'text' => DevelopmentProtectedKind.text,
      'recipient_ack' => DevelopmentProtectedKind.recipientAck,
      _ => throw const FormatException('BEST-V1 dev envelope kind'),
    };
    final messageId = '${map['messageId'] ?? ''}'.trim();
    final senderMmId = '${map['senderMmId'] ?? ''}'.trim();
    final recipientMmId = '${map['recipientMmId'] ?? ''}'.trim();
    if (messageId.isEmpty || senderMmId.isEmpty || recipientMmId.isEmpty) {
      throw const FormatException('BEST-V1 dev envelope identity fields');
    }
    final text = map['text'] is String ? map['text'] as String : null;
    final ackedMessageId =
        map['ackedMessageId'] is String ? map['ackedMessageId'] as String : null;
    if (kind == DevelopmentProtectedKind.text && text == null) {
      throw const FormatException('BEST-V1 text payload missing');
    }
    if (kind == DevelopmentProtectedKind.recipientAck &&
        (ackedMessageId == null || ackedMessageId.isEmpty)) {
      throw const FormatException('BEST-V1 ACK target missing');
    }
    return DevelopmentProtectedEvent(
      kind: kind,
      messageId: messageId,
      senderMmId: senderMmId,
      recipientMmId: recipientMmId,
      text: text,
      ackedMessageId: ackedMessageId,
    );
  }

  ProtectedEnvelope _encode(DevelopmentProtectedEvent event) {
    final payload = <String, Object?>{
      'schema': 'mesh-best-v1-dev/v1',
      'kind': switch (event.kind) {
        DevelopmentProtectedKind.text => 'text',
        DevelopmentProtectedKind.recipientAck => 'recipient_ack',
      },
      'messageId': event.messageId,
      'senderMmId': event.senderMmId,
      'recipientMmId': event.recipientMmId,
      if (event.text != null) 'text': event.text,
      if (event.ackedMessageId != null) 'ackedMessageId': event.ackedMessageId,
    };
    return ProtectedEnvelope(
      messageId: event.messageId,
      recipientMmId: event.recipientMmId,
      protectedBytes: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      cryptoVersion: 'DEV-NOT-PRODUCTION',
    );
  }
}
