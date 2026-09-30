import 'dart:typed_data';

import '../domain/message.dart';
import '../protocol/mmrp1_channel.dart';

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

/// Test/HIL-only compatibility provider.
///
/// This is intentionally NOT encryption. It maps the Best-v1 HIL text/receipt
/// path onto the same MMRP/1 CHANNEL/1 application wire used by MM U1 so the
/// LR24 HIL can prove cross-implementation compatibility. A production M07
/// provider must replace this before any security claim.
final class DevelopmentMessageProtector implements MessageProtector {
  const DevelopmentMessageProtector({
    this.localMmId = 'mm:local',
    this.channel = 'general',
  });

  final String localMmId;
  final String channel;
  static const Mmrp1ChannelCodec _codec = Mmrp1ChannelCodec();

  @override
  ProtectedEnvelope protect(LogicalMessage message) {
    return ProtectedEnvelope(
      messageId: message.messageId,
      recipientMmId: message.recipientMmId,
      protectedBytes: _codec.encode(
        Mmrp1ChannelData(
          from: localMmId,
          channel: channel,
          messageId: message.messageId,
          payload: message.text,
        ),
      ),
      cryptoVersion: 'DEV-MMRP1-PLAINTEXT-NOT-PRODUCTION',
    );
  }

  ProtectedEnvelope protectRecipientAck({
    required String ackedMessageId,
    required String recipientMmId,
  }) {
    return ProtectedEnvelope(
      messageId: 'receipt:${localMmId}:${ackedMessageId}',
      recipientMmId: recipientMmId,
      protectedBytes: _codec.encode(
        Mmrp1ChannelReceipt(
          from: localMmId,
          channel: channel,
          messageId: ackedMessageId,
        ),
      ),
      cryptoVersion: 'DEV-MMRP1-PLAINTEXT-NOT-PRODUCTION',
    );
  }

  DevelopmentProtectedEvent decode(Uint8List protectedBytes) {
    final frame = _codec.decode(protectedBytes);
    if (frame == null) {
      throw const FormatException('unsupported MMRP/1 CHANNEL frame');
    }

    switch (frame) {
      case Mmrp1ChannelData():
        return DevelopmentProtectedEvent(
          kind: DevelopmentProtectedKind.text,
          messageId: frame.messageId,
          senderMmId: frame.from,
          recipientMmId: localMmId,
          text: frame.payload,
        );
      case Mmrp1ChannelReceipt():
        return DevelopmentProtectedEvent(
          kind: DevelopmentProtectedKind.recipientAck,
          messageId: 'receipt:${frame.from}:${frame.messageId}',
          senderMmId: frame.from,
          recipientMmId: localMmId,
          ackedMessageId: frame.messageId,
        );
    }
  }
}
