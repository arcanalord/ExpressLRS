enum DeliveryState {
  created,
  queued,
  sentToTransport,
  delivered,
  failed,
}

final class LogicalMessage {
  const LogicalMessage({
    required this.messageId,
    required this.recipientMmId,
    required this.text,
  });

  final String messageId;
  final String recipientMmId;
  final String text;
}

final class RecipientAck {
  const RecipientAck({
    required this.messageId,
    required this.recipientMmId,
    required this.authenticated,
  });

  final String messageId;
  final String recipientMmId;
  final bool authenticated;
}
