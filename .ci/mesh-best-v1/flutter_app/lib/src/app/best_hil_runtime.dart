import 'dart:async';

import '../domain/message.dart';
import '../m02/delivery_engine.dart';
import '../m03/byte_stream_link.dart';
import '../m03/lr24_serial_adapter.dart';
import '../m03/transport_adapter.dart';
import '../m07/protector.dart';
import '../m12/router.dart';

sealed class BestHilEvent {
  const BestHilEvent();
}

final class BestHilIncomingText extends BestHilEvent {
  const BestHilIncomingText({
    required this.messageId,
    required this.senderMmId,
    required this.text,
  });

  final String messageId;
  final String senderMmId;
  final String text;
}

final class BestHilDeliveryUpdate extends BestHilEvent {
  const BestHilDeliveryUpdate({
    required this.messageId,
    required this.state,
  });

  final String messageId;
  final DeliveryState state;
}

final class BestHilTestProgress extends BestHilEvent {
  const BestHilTestProgress({
    required this.completed,
    required this.total,
    required this.delivered,
    required this.failed,
  });

  final int completed;
  final int total;
  final int delivered;
  final int failed;
}

final class BestHilTestResult {
  const BestHilTestResult({
    required this.total,
    required this.delivered,
    required this.failed,
    required this.elapsed,
  });

  final int total;
  final int delivered;
  final int failed;
  final Duration elapsed;

  bool get passed => delivered == total && failed == 0;
}

final class BestHilRuntime {
  BestHilRuntime({
    required this.localMmId,
    required this.peerMmId,
    required this.localBinding,
    required this.peerBinding,
    required Lr24ByteStreamLink link,
  })  : _protector = DevelopmentMessageProtector(localMmId: localMmId),
        _transport = Lr24SerialAdapter(
          link: link,
          localBinding: localBinding,
        ) {
    _engine = DeliveryEngine(
      protector: _protector,
      router: Lr24SingleRouteRouter(transportBinding: peerBinding),
      transport: _transport,
    );
    _subscription = _transport.inbound.listen(_onInbound);
  }

  final String localMmId;
  final String peerMmId;
  final String localBinding;
  final String peerBinding;

  final DevelopmentMessageProtector _protector;
  final Lr24SerialAdapter _transport;
  late final DeliveryEngine _engine;
  final InboundDeduper _deduper = InboundDeduper();
  final StreamController<BestHilEvent> _events =
      StreamController<BestHilEvent>.broadcast();
  StreamSubscription<TransportInboundFrame>? _subscription;
  int _messageCounter = 0;

  Stream<BestHilEvent> get events => _events.stream;

  Map<String, DeliveryRecord> get deliveries => _engine.records;

  bool get available => _transport.available;

  Future<DeliveryRecord> sendText(
    String text, {
    String? messageId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
    final id = messageId ??
        'best-${DateTime.now().microsecondsSinceEpoch}-${++_messageCounter}';
    final record = await _engine.sendText(
      recipientMmId: peerMmId,
      text: trimmed,
      messageId: id,
    );
    _events.add(
      BestHilDeliveryUpdate(messageId: id, state: record.state),
    );
    return record;
  }

  Future<BestHilTestResult> runTextTest({
    int count = 100,
    Duration ackTimeout = const Duration(seconds: 5),
  }) async {
    if (count < 1) {
      throw RangeError.range(count, 1, null, 'count');
    }
    final started = Stopwatch()..start();
    var delivered = 0;
    var failed = 0;
    final runId = DateTime.now().microsecondsSinceEpoch;

    for (var index = 1; index <= count; index++) {
      final messageId = 'hil-${runId}-${index}';
      final deliveredFuture = _waitForDelivered(
        messageId,
        timeout: ackTimeout,
      );
      final record = await sendText(
        'HIL TEST ${index}/${count}',
        messageId: messageId,
      );

      var ok = record.state == DeliveryState.delivered;
      if (!ok && record.state != DeliveryState.failed) {
        ok = await deliveredFuture;
      }
      if (ok) {
        delivered++;
      } else {
        failed++;
      }
      _events.add(
        BestHilTestProgress(
          completed: index,
          total: count,
          delivered: delivered,
          failed: failed,
        ),
      );
    }

    started.stop();
    return BestHilTestResult(
      total: count,
      delivered: delivered,
      failed: failed,
      elapsed: started.elapsed,
    );
  }

  Future<bool> _waitForDelivered(
    String messageId, {
    required Duration timeout,
  }) async {
    if (_engine.records[messageId]?.state == DeliveryState.delivered) {
      return true;
    }
    try {
      await events
          .whereType<BestHilDeliveryUpdate>()
          .firstWhere(
            (event) =>
                event.messageId == messageId &&
                event.state == DeliveryState.delivered,
          )
          .timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _onInbound(TransportInboundFrame frame) async {
    DevelopmentProtectedEvent event;
    try {
      event = _protector.decode(frame.protectedBytes);
    } on FormatException {
      return;
    }
    if (event.recipientMmId != localMmId) return;

    switch (event.kind) {
      case DevelopmentProtectedKind.text:
        if (_deduper.accept(event.messageId)) {
          _events.add(
            BestHilIncomingText(
              messageId: event.messageId,
              senderMmId: event.senderMmId,
              text: event.text!,
            ),
          );
        }
        await _sendRecipientAck(
          ackedMessageId: event.messageId,
          recipientMmId: event.senderMmId,
          transportBinding: frame.sourceBinding,
        );
      case DevelopmentProtectedKind.recipientAck:
        final acked = event.ackedMessageId!;
        final accepted = _engine.onRecipientAck(
          RecipientAck(
            messageId: acked,
            recipientMmId: event.senderMmId,
            // DEV-only HIL: successful decode of a dev envelope is treated as
            // authenticated solely to exercise application ACK ownership.
            authenticated: true,
          ),
        );
        if (accepted) {
          final record = _engine.records[acked];
          if (record != null) {
            _events.add(
              BestHilDeliveryUpdate(
                messageId: acked,
                state: record.state,
              ),
            );
          }
        }
    }
  }

  Future<void> _sendRecipientAck({
    required String ackedMessageId,
    required String recipientMmId,
    required String transportBinding,
  }) async {
    final envelope = _protector.protectRecipientAck(
      ackedMessageId: ackedMessageId,
      recipientMmId: recipientMmId,
    );
    final packet = Lr24SingleRouteRouter(
      transportBinding: transportBinding,
    ).prepare(envelope);
    await _transport.submit(packet);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _transport.close();
    await _events.close();
  }
}
