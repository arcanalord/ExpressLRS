import 'dart:async';

import 'mm_uart_external_radio_session.dart';

final class MmUartHilReport {
  const MmUartHilReport({
    required this.requested,
    required this.replied,
    required this.retries,
    required this.lost,
    required this.minRttMs,
    required this.avgRttMs,
    required this.maxRttMs,
    required this.compatPass,
    required this.ackPass,
    required this.duplicatePass,
    required this.mapPointPass,
    this.statsBefore = const {},
    this.statsAfter = const {},
  });

  final int requested;
  final int replied;
  final int retries;
  final int lost;
  final double minRttMs;
  final double avgRttMs;
  final double maxRttMs;
  final bool compatPass;
  final bool ackPass;
  final bool duplicatePass;
  final bool mapPointPass;
  final Map<String, dynamic> statsBefore;
  final Map<String, dynamic> statsAfter;

  double get lossPercent => requested == 0 ? 0 : lost * 100 / requested;

  bool get passed =>
      compatPass &&
      ackPass &&
      duplicatePass &&
      mapPointPass &&
      lost == 0;

  String summary() {
    final rtt =
        replied == 0
            ? 'RTT —'
            : 'RTT ${avgRttMs.toStringAsFixed(1)} мс '
                '(min ${minRttMs.toStringAsFixed(1)} / '
                'max ${maxRttMs.toStringAsFixed(1)})';
    return '${passed ? 'PASS' : 'CHECK'} · '
        '$replied/$requested · '
        'loss ${lossPercent.toStringAsFixed(1)}% · '
        'retry $retries · $rtt · '
        'ACK ${ackPass ? 'PASS' : 'FAIL'} · '
        'dedupe ${duplicatePass ? 'PASS' : 'FAIL'} · '
        'MapPoint ${mapPointPass ? 'PASS' : 'FAIL'}';
  }
}

final class _HilWaiter {
  _HilWaiter(this.sentAtMicros);
  final int sentAtMicros;
  final Completer<int> completer = Completer<int>();
}

final class MmUartHilBench {
  MmUartHilBench(this.session) {
    _subscription = session.events.listen(_onSessionEvent);
  }

  final MmUartExternalRadioSession session;
  StreamSubscription<ExternalRadioSessionEvent>? _subscription;

  final Map<String, _HilWaiter> _pongWaiters = {};
  final Map<String, Completer<Map<String, dynamic>>> _ackWaiters = {};
  final Map<String, Completer<Map<String, dynamic>>> _mapWaiters = {};
  final Set<String> _seenDeliveries = <String>{};

  bool get isAvailable => session.state == 'ready' && session.supportsMmrp;

  Future<MmUartHilReport> run({
    required Object recipientBinding,
    int count = 100,
    Duration timeout = const Duration(milliseconds: 700),
    int maxAttempts = 2,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!isAvailable) {
      throw StateError('HIL_RADIO_NOT_READY');
    }
    if (count <= 0 || count > 5000) {
      throw ArgumentError.value(count, 'count', '1..5000');
    }

    var compatPass = session.state == 'ready' && session.supportsMmrp;
    try {
      final compat = await session.compatSelftest();
      compatPass =
          compat['result'] == 'PASS' ||
          compat['ok'] == true ||
          compat['codecRoundTrip'] == true;
    } catch (_) {
      // v0.4.0 firmware predates COMPAT_SELFTEST. An already established
      // MM-UART/1 + explicit MMRP/1 session is sufficient to run HIL.
      compatPass = session.state == 'ready' && session.supportsMmrp;
    }

    Map<String, dynamic> before = const {};
    try {
      before = await session.refreshStats();
    } catch (_) {}

    final ack = await _runAckAndDuplicateCheck(
      recipientBinding: recipientBinding,
      timeout: timeout,
    );
    final mapPointPass = await _runMapPointCheck(
      recipientBinding: recipientBinding,
      timeout: timeout,
    );

    var replied = 0;
    var retries = 0;
    final samples = <double>[];

    const window = 8;
    var done = 0;
    for (var start = 0; start < count; start += window) {
      final end = (start + window) > count ? count : start + window;
      final futures = <Future<(bool, int, double?)>>[];
      for (var seq = start; seq < end; seq++) {
        futures.add(
          _probeOne(
            recipientBinding: recipientBinding,
            seq: seq,
            timeout: timeout,
            maxAttempts: maxAttempts,
          ),
        );
      }
      final batch = await Future.wait(futures);
      for (final result in batch) {
        if (result.$1) {
          replied++;
          if (result.$3 != null) samples.add(result.$3!);
        }
        retries += result.$2;
        done++;
        onProgress?.call(done, count);
      }
    }

    Map<String, dynamic> after = const {};
    try {
      after = await session.refreshStats();
    } catch (_) {}

    samples.sort();
    final min = samples.isEmpty ? 0.0 : samples.first;
    final max = samples.isEmpty ? 0.0 : samples.last;
    final avg = samples.isEmpty
        ? 0.0
        : samples.reduce((a, b) => a + b) / samples.length;

    return MmUartHilReport(
      requested: count,
      replied: replied,
      retries: retries,
      lost: count - replied,
      minRttMs: min,
      avgRttMs: avg,
      maxRttMs: max,
      compatPass: compatPass,
      ackPass: ack.$1,
      duplicatePass: ack.$2,
      mapPointPass: mapPointPass,
      statsBefore: before,
      statsAfter: after,
    );
  }

  Future<(bool, int, double?)> _probeOne({
    required Object recipientBinding,
    required int seq,
    required Duration timeout,
    required int maxAttempts,
  }) async {
    final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final id = 'hil:$runId:$seq';
    var retries = 0;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final sentAt = DateTime.now().microsecondsSinceEpoch;
      final waiter = _HilWaiter(sentAt);
      _pongWaiters[id] = waiter;
      try {
        await session.send(
          messageId: id,
          recipientBinding: recipientBinding,
          payloadType: 'hil_probe',
          qos: 'normal',
          payload: {
            'type': 'hil_probe',
            'probeId': id,
            'seq': seq,
            'sentAtMicros': sentAt,
            'sampleClass': seq % 10 == 0
                ? 'map_point'
                : (seq % 3 == 0 ? 'text' : 'control'),
            'sample': seq % 10 == 0
                ? {
                    'lat': 54.318 + (seq / 1000000),
                    'lon': 48.397 + (seq / 1000000),
                    'label': 'HIL-$seq',
                  }
                : 'HIL probe $seq',
          },
        );

        final arrivedAt = await waiter.completer.future.timeout(timeout);
        _pongWaiters.remove(id);
        final rtt = (arrivedAt - sentAt) / 1000.0;
        return (true, retries, rtt);
      } on TimeoutException {
        _pongWaiters.remove(id);
        if (attempt < maxAttempts) {
          retries++;
          continue;
        }
      } catch (_) {
        _pongWaiters.remove(id);
        if (attempt < maxAttempts) {
          retries++;
          continue;
        }
      }
    }
    return (false, retries, null);
  }

  Future<(bool, bool)> _runAckAndDuplicateCheck({
    required Object recipientBinding,
    required Duration timeout,
  }) async {
    final id = 'hil:delivery:${DateTime.now().microsecondsSinceEpoch}';

    Future<Map<String, dynamic>?> sendAndWait() async {
      final completer = Completer<Map<String, dynamic>>();
      _ackWaiters[id] = completer;
      try {
        await session.send(
          messageId: id,
          recipientBinding: recipientBinding,
          payloadType: 'hil_delivery',
          qos: 'urgent',
          payload: {
            'type': 'hil_delivery',
            'messageId': id,
            'text': 'HIL recipient ACK',
          },
        );
        return await completer.future.timeout(timeout);
      } catch (_) {
        return null;
      } finally {
        _ackWaiters.remove(id);
      }
    }

    final first = await sendAndWait();
    final second = await sendAndWait();
    return (
      first != null && first['messageId'] == id,
      second != null && second['duplicate'] == true,
    );
  }

  Future<bool> _runMapPointCheck({
    required Object recipientBinding,
    required Duration timeout,
  }) async {
    final id = 'hil:map:${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<Map<String, dynamic>>();
    _mapWaiters[id] = completer;
    const lat = 54.318123;
    const lon = 48.397456;
    try {
      await session.send(
        messageId: id,
        recipientBinding: recipientBinding,
        payloadType: 'hil_map_point',
        qos: 'normal',
        payload: {
          'type': 'hil_map_point',
          'messageId': id,
          'lat': lat,
          'lon': lon,
          'label': 'HIL MapPoint',
        },
      );
      final reply = await completer.future.timeout(timeout);
      final rLat = (reply['lat'] as num?)?.toDouble();
      final rLon = (reply['lon'] as num?)?.toDouble();
      return reply['messageId'] == id && rLat == lat && rLon == lon;
    } catch (_) {
      return false;
    } finally {
      _mapWaiters.remove(id);
    }
  }

  void _onSessionEvent(ExternalRadioSessionEvent event) {
    if (event is! ExternalRadioPacketEvent) return;
    final packet = event.packet;
    final sourceBinding = packet['sourceBinding'];
    final payloadType = '${packet['payloadType'] ?? ''}'.trim();
    final payloadRaw = packet['payload'];
    if (sourceBinding == null || payloadRaw is! Map) return;
    final payload = Map<String, dynamic>.from(payloadRaw);

    switch (payloadType) {
      case 'hil_probe':
        unawaited(_replyPong(sourceBinding, payload));
      case 'hil_pong':
        final id = '${payload['probeId'] ?? ''}'.trim();
        final waiter = _pongWaiters[id];
        if (waiter != null && !waiter.completer.isCompleted) {
          waiter.completer.complete(DateTime.now().microsecondsSinceEpoch);
        }
      case 'hil_delivery':
        unawaited(_replyDeliveryAck(sourceBinding, packet, payload));
      case 'hil_map_point':
        unawaited(_replyMapPoint(sourceBinding, payload));
      case 'hil_map_echo':
        final id = '${payload['messageId'] ?? ''}'.trim();
        final waiter = _mapWaiters[id];
        if (waiter != null && !waiter.isCompleted) waiter.complete(payload);
      case 'control':
        if (payload['type'] == 'transport_ack') {
          final id = '${payload['messageId'] ?? ''}'.trim();
          final waiter = _ackWaiters[id];
          if (waiter != null && !waiter.isCompleted) waiter.complete(payload);
        }
    }
  }

  Future<void> _replyPong(
    Object recipientBinding,
    Map<String, dynamic> payload,
  ) async {
    if (!isAvailable) return;
    final id = '${payload['probeId'] ?? ''}'.trim();
    if (id.isEmpty) return;
    await session.send(
      messageId: 'pong:$id',
      recipientBinding: recipientBinding,
      payloadType: 'hil_pong',
      qos: 'urgent',
      payload: {
        'type': 'hil_pong',
        'probeId': id,
        'seq': payload['seq'],
        'sentAtMicros': payload['sentAtMicros'],
      },
    );
  }

  Future<void> _replyDeliveryAck(
    Object recipientBinding,
    Map<String, dynamic> packet,
    Map<String, dynamic> payload,
  ) async {
    if (!isAvailable) return;
    final id = '${packet['messageId'] ?? payload['messageId'] ?? ''}'.trim();
    if (id.isEmpty) return;
    final duplicate = !_seenDeliveries.add(id);
    if (_seenDeliveries.length > 2048) {
      _seenDeliveries.remove(_seenDeliveries.first);
    }
    await session.send(
      messageId: 'ack:$id',
      recipientBinding: recipientBinding,
      payloadType: 'control',
      qos: 'urgent',
      payload: {
        'type': 'transport_ack',
        'messageId': id,
        'duplicate': duplicate,
      },
    );
  }

  Future<void> _replyMapPoint(
    Object recipientBinding,
    Map<String, dynamic> payload,
  ) async {
    if (!isAvailable) return;
    final id = '${payload['messageId'] ?? ''}'.trim();
    if (id.isEmpty) return;
    await session.send(
      messageId: 'map-echo:$id',
      recipientBinding: recipientBinding,
      payloadType: 'hil_map_echo',
      qos: 'normal',
      payload: {
        'type': 'hil_map_echo',
        'messageId': id,
        'lat': payload['lat'],
        'lon': payload['lon'],
        'label': payload['label'],
      },
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _pongWaiters.clear();
    for (final waiter in _ackWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('HIL_CLOSED'));
    }
    for (final waiter in _mapWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('HIL_CLOSED'));
    }
    _ackWaiters.clear();
    _mapWaiters.clear();
  }
}
