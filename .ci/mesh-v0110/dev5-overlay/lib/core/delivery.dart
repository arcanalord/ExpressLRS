import 'dart:async';

import 'app_storage.dart';
import 'models.dart';

enum TransportSendStatus { accepted, rejected, unavailable }

final class TransportSendResult {
  const TransportSendResult(this.status, {this.detail});
  final TransportSendStatus status;
  final String? detail;
}

abstract interface class MessageTransport {
  String get id;
  bool get isAvailable;
  Future<TransportSendResult> send(DeliveryEnvelope envelope);
}

final class DeliveryManager {
  DeliveryManager({
    required AppStorage storage,
    required List<MessageTransport> transports,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 5),
    this.maxAttempts = 5,
    this.maxPending = 512,
  }) : _storage = storage,
       _transports = transports,
       _now = now ?? (() => DateTime.now().toUtc());

  final AppStorage _storage;
  final List<MessageTransport> _transports;
  final DateTime Function() _now;
  final Duration retryDelay;
  final int maxAttempts;
  final int maxPending;
  final Map<String, DeliveryEnvelope> _items = {};
  final StreamController<DeliveryEnvelope> _changes =
      StreamController.broadcast();
  int _idCounter = 0;

  Stream<DeliveryEnvelope> get changes => _changes.stream;
  List<DeliveryEnvelope> get pending =>
      List.unmodifiable(_items.values.where((e) => !e.state.isTerminal));
  DeliveryEnvelope? byId(String id) => _items[id];

  Future<void> restore() async {
    final loaded = await _storage.loadOutbox();
    _items.clear();
    for (final original in loaded) {
      // A process restart invalidates transport-local in-flight state. Never
      // leave a persisted item stuck in sending/waitingAck after restart.
      final restored = switch (original.state) {
        DeliveryState.sending || DeliveryState.waitingAck => original.copyWith(
          state: DeliveryState.queued,
          clearSelectedTransport: true,
          clearNextRetryAt: true,
        ),
        _ => original,
      };
      _items[restored.messageId] = restored;
      if (!identical(restored, original)) {
        await _storage.saveOutboxItem(restored);
      }
    }
  }

  Future<DeliveryEnvelope> sendText({
    required String recipientMmId,
    required String text,
    Duration ttl = const Duration(days: 7),
  }) => enqueue(
    recipientMmId: recipientMmId,
    messageClass: 'text',
    payload: text,
    ttl: ttl,
  );

  Future<DeliveryEnvelope> enqueue({
    required String recipientMmId,
    required String messageClass,
    required String payload,
    Duration ttl = const Duration(days: 7),
    int priority = 0,
  }) async {
    if (pending.length >= maxPending) {
      throw StateError('outbox capacity exceeded');
    }
    final now = _now();
    final envelope = DeliveryEnvelope(
      messageId: 'm-${now.microsecondsSinceEpoch}-${++_idCounter}',
      recipientMmId: recipientMmId,
      messageClass: messageClass,
      payload: payload,
      createdAt: now,
      expiresAt: now.add(ttl),
      priority: priority,
      state: DeliveryState.queued,
    );
    await _save(envelope);
    return await dispatch(envelope.messageId) ?? envelope;
  }

  Future<DeliveryEnvelope?> dispatch(String messageId) async {
    final current = _items[messageId];
    if (current == null || current.state.isTerminal) return current;
    if (!_now().isBefore(current.expiresAt)) {
      return _save(current.copyWith(state: DeliveryState.expired));
    }

    final candidates = _transports.where((t) => t.isAvailable).toList();
    if (candidates.isEmpty) {
      return _save(
        current.copyWith(
          state: DeliveryState.noRoute,
          clearSelectedTransport: true,
        ),
      );
    }

    var latest = current.copyWith(
      state: DeliveryState.sending,
      attempts: current.attempts + 1,
      clearLastError: true,
      clearNextRetryAt: true,
    );
    await _save(latest);

    String? lastDetail;
    var allUnavailable = true;
    for (final transport in candidates) {
      latest = (_items[messageId] ?? latest).copyWith(
        state: DeliveryState.sending,
        selectedTransportId: transport.id,
      );
      await _save(latest);
      final result = await transport.send(latest);
      latest = _items[messageId] ?? latest;
      if (result.status == TransportSendStatus.accepted) {
        allUnavailable = false;
        // ACK may arrive while send() is still returning; never overwrite it.
        if (latest.state != DeliveryState.sending) return latest;
        return _save(latest.copyWith(state: DeliveryState.waitingAck));
      }
      if (result.status != TransportSendStatus.unavailable) {
        allUnavailable = false;
      }
      lastDetail = result.detail;
    }

    if (allUnavailable) {
      return _save(
        latest.copyWith(
          state: DeliveryState.retryWait,
          attempts: current.attempts,
          lastError: lastDetail,
          nextRetryAt: _now().add(retryDelay),
          clearSelectedTransport: true,
        ),
      );
    }

    if (latest.attempts >= maxAttempts) {
      return _save(
        latest.copyWith(state: DeliveryState.failed, lastError: lastDetail),
      );
    }
    return _save(
      latest.copyWith(
        state: DeliveryState.retryWait,
        lastError: lastDetail,
        nextRetryAt: _now().add(retryDelay),
      ),
    );
  }

  Future<DeliveryEnvelope?> acknowledge({
    required String messageId,
    required String fromMmId,
  }) => recipientResult(messageId: messageId, fromMmId: fromMmId, ok: true);

  Future<DeliveryEnvelope?> recipientResult({
    required String messageId,
    required String fromMmId,
    required bool ok,
    String? detail,
  }) async {
    final current = _items[messageId];
    if (current == null || current.state.isTerminal) return current;
    if (current.recipientMmId != fromMmId) return current;
    if (ok) return _save(current.copyWith(state: DeliveryState.delivered));
    if (current.attempts >= maxAttempts) {
      return _save(
        current.copyWith(state: DeliveryState.failed, lastError: detail),
      );
    }
    return _save(
      current.copyWith(
        state: DeliveryState.retryWait,
        lastError: detail,
        nextRetryAt: _now().add(retryDelay),
      ),
    );
  }

  Future<void> maintenance() async {
    final now = _now();
    final redispatch = <String>[];
    for (final item in List<DeliveryEnvelope>.from(_items.values)) {
      if (item.state.isTerminal) continue;
      if (!now.isBefore(item.expiresAt)) {
        await _save(item.copyWith(state: DeliveryState.expired));
      } else if (item.state == DeliveryState.retryWait &&
          item.nextRetryAt != null &&
          !now.isBefore(item.nextRetryAt!)) {
        await _save(
          item.copyWith(
            state: DeliveryState.queued,
            clearNextRetryAt: true,
            clearSelectedTransport: true,
          ),
        );
        redispatch.add(item.messageId);
      } else if (item.state == DeliveryState.noRoute &&
          _transports.any((t) => t.isAvailable)) {
        await _save(
          item.copyWith(
            state: DeliveryState.queued,
            clearSelectedTransport: true,
          ),
        );
        redispatch.add(item.messageId);
      }
    }
    for (final messageId in redispatch) {
      await dispatch(messageId);
    }
  }

  Future<DeliveryEnvelope> _save(DeliveryEnvelope item) async {
    _items[item.messageId] = item;
    if (item.state.isTerminal) {
      await _storage.removeOutboxItem(item.messageId);
    } else {
      await _storage.saveOutboxItem(item);
    }
    _changes.add(item);
    return item;
  }

  Future<void> close() => _changes.close();
}
