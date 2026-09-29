import '../domain/message.dart';
import '../m03/transport_adapter.dart';
import '../m07/protector.dart';
import '../m12/router.dart';

final class DeliveryRecord {
  DeliveryRecord({
    required this.message,
    required this.state,
  });

  final LogicalMessage message;
  DeliveryState state;
}

final class DeliveryEngine {
  DeliveryEngine({
    required MessageProtector protector,
    required SingleRouteRouter router,
    required PreparedTransportAdapter transport,
  })  : _protector = protector,
        _router = router,
        _transport = transport;

  final MessageProtector _protector;
  final SingleRouteRouter _router;
  final PreparedTransportAdapter _transport;
  final Map<String, DeliveryRecord> _records = <String, DeliveryRecord>{};
  int _counter = 0;

  Map<String, DeliveryRecord> get records =>
      Map<String, DeliveryRecord>.unmodifiable(_records);

  Future<DeliveryRecord> sendText({
    required String recipientMmId,
    required String text,
    String? messageId,
  }) async {
    final id = messageId ?? 'msg-${++_counter}';
    final existing = _records[id];
    if (existing != null) {
      final retryResult = await _submit(existing.message);
      if (retryResult.status == TransportSubmitStatus.accepted &&
          existing.state != DeliveryState.delivered) {
        existing.state = DeliveryState.sentToTransport;
      }
      return existing;
    }

    final message = LogicalMessage(
      messageId: id,
      recipientMmId: recipientMmId,
      text: text,
    );
    final record = DeliveryRecord(
      message: message,
      state: DeliveryState.created,
    );
    _records[id] = record;
    record.state = DeliveryState.queued;

    final result = await _submit(message);
    record.state = switch (result.status) {
      TransportSubmitStatus.accepted => DeliveryState.sentToTransport,
      TransportSubmitStatus.unavailable => DeliveryState.queued,
      TransportSubmitStatus.rejected => DeliveryState.failed,
    };
    return record;
  }

  Future<TransportSubmitResult> _submit(LogicalMessage message) {
    final envelope = _protector.protect(message);
    final packet = _router.prepare(envelope);
    return _transport.submit(packet);
  }

  bool onRecipientAck(RecipientAck ack) {
    final record = _records[ack.messageId];
    if (record == null) return false;
    if (!ack.authenticated) return false;
    if (ack.recipientMmId != record.message.recipientMmId) return false;
    record.state = DeliveryState.delivered;
    return true;
  }
}

final class InboundDeduper {
  final Set<String> _seenMessageIds = <String>{};

  bool accept(String messageId) => _seenMessageIds.add(messageId);
}
