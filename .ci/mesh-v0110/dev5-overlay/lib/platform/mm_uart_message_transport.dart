import 'dart:async';
import 'dart:convert';

import '../core/delivery.dart';
import '../core/models.dart';
import 'mm_uart_external_radio_session.dart';

sealed class MmUartMessageTransportEvent {
  const MmUartMessageTransportEvent();
}

final class MmUartIncomingMessage extends MmUartMessageTransportEvent {
  const MmUartIncomingMessage({
    required this.messageId,
    required this.sourceBinding,
    required this.messageClass,
    required this.payload,
  });
  final String messageId;
  final Object sourceBinding;
  final String messageClass;
  final Object payload;
}

final class MmUartRecipientAck extends MmUartMessageTransportEvent {
  const MmUartRecipientAck({
    required this.messageId,
    required this.sourceBinding,
  });
  final String messageId;
  final Object sourceBinding;
}

final class MmUartMessageTransport implements MessageTransport {
  MmUartMessageTransport({
    required this.session,
    required Object? Function(String mmId) resolveRecipientBinding,
  }) : _resolveRecipientBinding = resolveRecipientBinding {
    _subscription = session.events.listen(_onSessionEvent);
  }

  final MmUartExternalRadioSession session;
  final Object? Function(String mmId) _resolveRecipientBinding;
  final StreamController<MmUartMessageTransportEvent> _events =
      StreamController.broadcast();
  StreamSubscription<ExternalRadioSessionEvent>? _subscription;

  Stream<MmUartMessageTransportEvent> get events => _events.stream;

  @override
  String get id => 'external-radio';

  @override
  bool get isAvailable => session.state == 'ready' && session.supportsMmrp;

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    if (!isAvailable) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'EXTERNAL_RADIO_NOT_READY_OR_NO_MMRP',
      );
    }
    final binding = _resolveRecipientBinding(envelope.recipientMmId);
    if (binding == null || '$binding'.trim().isEmpty) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'EXTERNAL_RADIO_BINDING_REQUIRED',
      );
    }

    Object payload;
    switch (envelope.messageClass) {
      case 'text':
        payload = {'text': envelope.payload};
      case 'map_point':
        try {
          final decoded = jsonDecode(envelope.payload);
          if (decoded is! Map) throw const FormatException('MAP_POINT_INVALID');
          payload = Map<String, dynamic>.from(decoded);
        } catch (_) {
          return const TransportSendResult(
            TransportSendStatus.rejected,
            detail: 'MAP_POINT_INVALID',
          );
        }
      default:
        return TransportSendResult(
          TransportSendStatus.unavailable,
          detail: 'EXTERNAL_RADIO_CLASS_UNSUPPORTED:${envelope.messageClass}',
        );
    }

    try {
      // SEND/RESPONSE only means the radio accepted the packet handling request.
      // M02 keeps the envelope in waitingAck until MmUartRecipientAck arrives.
      final result = await session.send(
        messageId: envelope.messageId,
        recipientBinding: '$binding',
        payload: payload,
        payloadType: envelope.messageClass,
        qos: envelope.priority > 0 ? 'urgent' : 'normal',
      );
      final accepted = result is Map ? result['accepted'] != false : true;
      return accepted
          ? const TransportSendResult(TransportSendStatus.accepted)
          : const TransportSendResult(
              TransportSendStatus.rejected,
              detail: 'EXTERNAL_RADIO_SEND_REJECTED',
            );
    } catch (error) {
      return TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'EXTERNAL_RADIO_SEND_FAILED:$error',
      );
    }
  }

  Future<void> acknowledgeIncoming({
    required String messageId,
    required Object recipientBinding,
  }) async {
    await session.send(
      messageId: 'ack-$messageId',
      recipientBinding: '$recipientBinding',
      payload: {'type': 'transport_ack', 'messageId': messageId},
      payloadType: 'control',
      qos: 'urgent',
    );
  }

  void _onSessionEvent(ExternalRadioSessionEvent event) {
    if (event is! ExternalRadioPacketEvent) return;
    final packet = event.packet;
    final messageId = '${packet['messageId'] ?? ''}'.trim();
    final sourceBinding = packet['sourceBinding'];
    final payload = packet['payload'];
    if (messageId.isEmpty || sourceBinding == null || payload == null) return;

    if (payload is Map && payload['type'] == 'transport_ack') {
      final acked = '${payload['messageId'] ?? ''}'.trim();
      if (acked.isNotEmpty) {
        _events.add(
          MmUartRecipientAck(messageId: acked, sourceBinding: sourceBinding),
        );
      }
      return;
    }

    var messageClass = '${packet['payloadType'] ?? ''}'.trim();
    if (messageClass.isEmpty && payload is Map) {
      messageClass = '${payload['type'] ?? ''}'.trim();
    }
    if (messageClass.isEmpty) messageClass = 'data';
    _events.add(
      MmUartIncomingMessage(
        messageId: messageId,
        sourceBinding: sourceBinding,
        messageClass: messageClass,
        payload: payload,
      ),
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _events.close();
  }
}
