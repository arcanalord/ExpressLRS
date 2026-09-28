import 'dart:io';

import '../lib/core/app_storage.dart';
import '../lib/core/delivery.dart';
import '../lib/core/models.dart';

final class _MutableTransport implements MessageTransport {
  _MutableTransport({
    this.available = true,
    this.status = TransportSendStatus.accepted,
    this.detail,
  });

  bool available;
  TransportSendStatus status;
  String? detail;
  int sends = 0;

  @override
  String get id => 'm02-reliability-test';

  @override
  bool get isAvailable => available;

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    sends++;
    return TransportSendResult(status, detail: detail);
  }
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('mesh_m02_reliable_');
  var now = DateTime.utc(2026, 9, 28, 18);
  final storage = AppStorage(root);
  final transport = _MutableTransport(
    status: TransportSendStatus.rejected,
    detail: 'TEMP_ROUTE_ERROR',
  );

  try {
    final delivery = DeliveryManager(
      storage: storage,
      transports: <MessageTransport>[transport],
      now: () => now,
      retryDelay: const Duration(milliseconds: 100),
      maxRetryDelay: const Duration(milliseconds: 500),
      maxAttempts: 2,
    );
    await delivery.restore();

    var item = await delivery.enqueue(
      recipientMmId: 'mm:peer',
      messageClass: 'text',
      payload: 'persistent retry',
      ttl: const Duration(hours: 1),
    );
    final stableMessageId = item.messageId;
    if (item.state != DeliveryState.retryWait || item.state.isTerminal) {
      throw StateError('Retryable transport rejection became terminal');
    }

    for (var i = 0; i < 4; i++) {
      final retryAt = item.nextRetryAt;
      if (retryAt == null) throw StateError('Retry deadline missing');
      now = retryAt.add(const Duration(milliseconds: 1));
      await delivery.maintenance();
      item = delivery.byId(stableMessageId)!;
      if (item.state != DeliveryState.retryWait || item.state.isTerminal) {
        throw StateError('Retry budget incorrectly caused terminal failure');
      }
      if (item.messageId != stableMessageId) {
        throw StateError('Retry changed logical messageId');
      }
    }

    transport.status = TransportSendStatus.accepted;
    transport.detail = null;
    now = item.nextRetryAt!.add(const Duration(milliseconds: 1));
    await delivery.maintenance();
    item = delivery.byId(stableMessageId)!;
    if (item.state != DeliveryState.waitingAck) {
      throw StateError('Recovered route did not return to WAITING_ACK');
    }
    final delivered = await delivery.acknowledge(
      messageId: stableMessageId,
      fromMmId: 'mm:peer',
    );
    if (delivered?.state != DeliveryState.delivered) {
      throw StateError('Recipient ACK did not produce Delivered');
    }
    if ((await storage.loadOutbox()).isNotEmpty) {
      throw StateError('Delivered message remained in persistent outbox');
    }
    await delivery.close();

    transport.available = false;
    transport.status = TransportSendStatus.accepted;
    final beforeRestart = DeliveryManager(
      storage: storage,
      transports: <MessageTransport>[transport],
      now: () => now,
      retryDelay: const Duration(milliseconds: 100),
      maxRetryDelay: const Duration(milliseconds: 500),
    );
    final queuedOffline = await beforeRestart.enqueue(
      recipientMmId: 'mm:offline-peer',
      messageClass: 'text',
      payload: 'survive restart',
    );
    if (queuedOffline.state != DeliveryState.noRoute ||
        queuedOffline.state.isTerminal) {
      throw StateError('No-route message must remain pending');
    }
    final offlineMessageId = queuedOffline.messageId;
    await beforeRestart.close();

    transport.available = true;
    final afterRestart = DeliveryManager(
      storage: storage,
      transports: <MessageTransport>[transport],
      now: () => now,
      retryDelay: const Duration(milliseconds: 100),
      maxRetryDelay: const Duration(milliseconds: 500),
    );
    await afterRestart.restore();
    final restored = afterRestart.byId(offlineMessageId);
    if (restored == null || restored.messageId != offlineMessageId) {
      throw StateError('Restart lost pending logical message');
    }
    await afterRestart.maintenance();
    final resumed = afterRestart.byId(offlineMessageId);
    if (resumed?.state != DeliveryState.waitingAck) {
      throw StateError('Restored no-route message did not resume');
    }
    await afterRestart.acknowledge(
      messageId: offlineMessageId,
      fromMmId: 'mm:offline-peer',
    );

    const groupMessageId = 'gm-persistence';
    final legB = await afterRestart.enqueue(
      recipientMmId: groupTargetKey('g-test', 'mm:b'),
      messageClass: 'text',
      payload: 'group',
      messageId: groupMessageId,
      deliveryId: '$groupMessageId@mm:b',
      groupRevision: 1,
    );
    final legC = await afterRestart.enqueue(
      recipientMmId: groupTargetKey('g-test', 'mm:c'),
      messageClass: 'text',
      payload: 'group',
      messageId: groupMessageId,
      deliveryId: '$groupMessageId@mm:c',
      groupRevision: 1,
    );
    if (legB.state != DeliveryState.waitingAck ||
        legC.state != DeliveryState.waitingAck) {
      throw StateError('Group legs did not enter WAITING_ACK');
    }
    await afterRestart.recipientResult(
      messageId: groupMessageId,
      fromMmId: 'mm:b',
      ok: false,
      detail: 'ACK_TIMEOUT',
    );
    final persistedLegs = (await storage.loadOutbox())
        .where((item) => item.messageId == groupMessageId)
        .toList(growable: false);
    if (persistedLegs.length != 2 ||
        persistedLegs.map((item) => item.effectiveDeliveryId).toSet().length !=
            2) {
      throw StateError('Persistent outbox corrupted independent group legs');
    }
    if (persistedLegs
            .where((item) => item.groupMemberMmId == 'mm:b')
            .single
            .state !=
        DeliveryState.retryWait) {
      throw StateError('Retry state for one group leg was not persisted');
    }
    if (persistedLegs
            .where((item) => item.groupMemberMmId == 'mm:c')
            .single
            .state !=
        DeliveryState.waitingAck) {
      throw StateError('Retry of one group leg modified another leg');
    }
    await afterRestart.recipientResult(
      messageId: groupMessageId,
      fromMmId: 'mm:b',
      ok: true,
    );
    await afterRestart.recipientResult(
      messageId: groupMessageId,
      fromMmId: 'mm:c',
      ok: true,
    );

    transport.status = TransportSendStatus.hardRejected;
    transport.detail = 'POLICY_REJECTED';
    final hard = await afterRestart.enqueue(
      recipientMmId: 'mm:blocked-peer',
      messageClass: 'text',
      payload: 'must fail hard',
    );
    if (hard.state != DeliveryState.failed ||
        hard.lastError != 'POLICY_REJECTED') {
      throw StateError('Explicit hard failure did not become terminal');
    }

    await afterRestart.close();
  } finally {
    if (await root.exists()) await root.delete(recursive: true);
  }

  stdout.writeln('MESH_MESSENGER_M02_RELIABLE_DELIVERY_PASS');
}
