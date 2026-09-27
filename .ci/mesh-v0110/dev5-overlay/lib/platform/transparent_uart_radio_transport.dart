import 'dart:async';
import 'dart:typed_data';

import '../core/delivery.dart';
import '../core/models.dart';
import 'android_usb_serial_bridge.dart';
import 'mm_serial_codec.dart';

sealed class TransparentUartRadioEvent {
  const TransparentUartRadioEvent();
}

final class TransparentUartStateEvent extends TransparentUartRadioEvent {
  const TransparentUartStateEvent(this.state, {this.error});
  final String state;
  final String? error;
}

final class TransparentUartIncomingMessage extends TransparentUartRadioEvent {
  const TransparentUartIncomingMessage({
    required this.messageId,
    required this.fromMmId,
    required this.messageClass,
    required this.payload,
  });

  final String messageId;
  final String fromMmId;
  final String messageClass;
  final String payload;
}

final class TransparentUartRecipientAck extends TransparentUartRadioEvent {
  const TransparentUartRecipientAck({
    required this.messageId,
    required this.fromMmId,
  });

  final String messageId;
  final String fromMmId;
}

final class TransparentUartProbeResult extends TransparentUartRadioEvent {
  const TransparentUartProbeResult({
    required this.peerMmId,
    required this.rttMillis,
  });

  final String peerMmId;
  final int rttMillis;
}

final class TransparentUartStatsEvent extends TransparentUartRadioEvent {
  const TransparentUartStatsEvent({
    required this.txBytes,
    required this.rxBytes,
    required this.txFrames,
    required this.rxFrames,
    required this.badFrames,
  });

  final int txBytes;
  final int rxBytes;
  final int txFrames;
  final int rxFrames;
  final int badFrames;
}

final class _PendingProbe {
  _PendingProbe(this.started, this.completer, this.timer);
  final DateTime started;
  final Completer<Duration> completer;
  final Timer timer;
}

/// MessageTransport for stock transparent UART radios such as MicoAir LR24-F.
///
/// The modem is not probed or reflashed. It only carries MM-SERIAL/1 bytes.
final class TransparentUartRadioTransport implements MessageTransport {
  TransparentUartRadioTransport({
    required AndroidUsbSerialBridge bridge,
    required this.ownMmId,
  }) : _bridge = bridge;

  final AndroidUsbSerialBridge _bridge;
  final String ownMmId;
  final MmSerialCodec _codec = MmSerialCodec();
  final StreamController<TransparentUartRadioEvent> _events =
      StreamController<TransparentUartRadioEvent>.broadcast();
  StreamSubscription<AndroidUsbSerialEvent>? _subscription;
  final Map<String, _PendingProbe> _probes = <String, _PendingProbe>{};

  String state = 'disconnected';
  String? lastError;
  int? deviceId;
  int baudRate = 57600;
  int txBytes = 0;
  int rxBytes = 0;
  int txFrames = 0;
  int rxFrames = 0;

  Stream<TransparentUartRadioEvent> get events => _events.stream;

  @override
  String get id => 'lr24-usb';

  @override
  bool get isAvailable => state == 'ready';

  int get badFrames => _codec.badFrames;

  Future<void> connect(int id, {int baudRate = 57600}) async {
    await _subscription?.cancel();
    _subscription = _bridge.events.listen(_onBridgeEvent);
    _codec.reset();
    _failProbes(StateError('LR24 reconnect'));
    txBytes = 0;
    rxBytes = 0;
    txFrames = 0;
    rxFrames = 0;
    lastError = null;
    deviceId = id;
    this.baudRate = baudRate;
    state = 'connecting';
    _events.add(const TransparentUartStateEvent('connecting'));
    try {
      await _bridge.connect(id, baudRate: baudRate);
    } catch (error) {
      state = 'error';
      lastError = error.toString();
      _events.add(TransparentUartStateEvent('error', error: lastError));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _bridge.disconnect();
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _codec.reset();
      _failProbes(StateError('LR24 disconnected'));
      deviceId = null;
      state = 'disconnected';
      _events.add(const TransparentUartStateEvent('disconnected'));
    }
  }

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    if (!isAvailable) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LR24_NOT_READY',
      );
    }
    if (envelope.messageClass != 'text' &&
        envelope.messageClass != 'map_point') {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LR24_CLASS_UNSUPPORTED',
      );
    }
    final frame = <String, Object?>{
      'v': 1,
      'p': 'MMRP/1',
      'k': 'data',
      'id': envelope.messageId,
      'from': ownMmId,
      'to': envelope.recipientMmId,
      'class': envelope.messageClass,
      'q': envelope.priority,
      'payload': envelope.payload,
    };
    try {
      await _writeFrame(frame);
      return const TransportSendResult(TransportSendStatus.accepted);
    } catch (error) {
      return TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'LR24_WRITE_FAILED:' + error.toString(),
      );
    }
  }

  Future<void> acknowledgeIncoming({
    required String messageId,
    required String toMmId,
  }) =>
      _writeFrame(<String, Object?>{
        'v': 1,
        'p': 'MMRP/1',
        'k': 'ack',
        'id': messageId,
        'from': ownMmId,
        'to': toMmId,
      });

  Future<Duration> probe(
    String peerMmId, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!isAvailable) throw StateError('LR24_NOT_READY');
    final nonce = DateTime.now().microsecondsSinceEpoch.toString() +
        '-' +
        (_probes.length + 1).toString();
    final completer = Completer<Duration>();
    late final Timer timer;
    timer = Timer(timeout, () {
      final pending = _probes.remove(nonce);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          TimeoutException('LR24 probe timeout', timeout),
        );
      }
    });
    _probes[nonce] = _PendingProbe(DateTime.now(), completer, timer);
    try {
      await _writeFrame(<String, Object?>{
        'v': 1,
        'p': 'MMRP/1',
        'k': 'ping',
        'n': nonce,
        'from': ownMmId,
        'to': peerMmId,
      });
    } catch (error, stackTrace) {
      final pending = _probes.remove(nonce);
      pending?.timer.cancel();
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  Future<void> _writeFrame(Map<String, Object?> frame) async {
    final bytes = _codec.encode(frame);
    await _bridge.write(bytes);
    txBytes += bytes.length;
    txFrames++;
    _emitStats();
  }

  void _onBridgeEvent(AndroidUsbSerialEvent event) {
    if (event is AndroidUsbSerialState) {
      final next = (event.status['state'] ?? '').toString().trim().toLowerCase();
      final error = event.status['error']?.toString();
      if (next == 'ready' || next == 'connected') {
        state = 'ready';
        lastError = null;
        _events.add(const TransparentUartStateEvent('ready'));
      } else if (next == 'permission') {
        state = 'permission';
        _events.add(const TransparentUartStateEvent('permission'));
      } else if (next == 'permission_denied' || next == 'error') {
        state = 'error';
        lastError = error ?? next;
        _events.add(TransparentUartStateEvent('error', error: lastError));
      } else if (next == 'offline' ||
          next == 'disconnected' ||
          next == 'detached') {
        state = 'disconnected';
        _codec.reset();
        _failProbes(StateError('LR24 disconnected'));
        _events.add(const TransparentUartStateEvent('disconnected'));
      }
      return;
    }

    if (event is AndroidUsbSerialBytes) {
      rxBytes += event.bytes.length;
      final beforeBad = _codec.badFrames;
      final frames = _codec.feed(Uint8List.fromList(event.bytes));
      if (_codec.badFrames != beforeBad) _emitStats();
      for (final frame in frames) {
        rxFrames++;
        _handleFrame(frame);
      }
      _emitStats();
    }
  }

  void _handleFrame(Map<String, dynamic> frame) {
    if (frame['p'] != 'MMRP/1' || frame['v'] != 1) return;
    final to = (frame['to'] ?? '').toString().trim();
    if (to.isNotEmpty && to != ownMmId && to != '*') return;
    final from = (frame['from'] ?? '').toString().trim();
    if (from.isEmpty || from == ownMmId) return;
    final kind = (frame['k'] ?? '').toString().trim();

    switch (kind) {
      case 'ack':
        final id = (frame['id'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          _events.add(
            TransparentUartRecipientAck(messageId: id, fromMmId: from),
          );
        }
      case 'data':
        final id = (frame['id'] ?? '').toString().trim();
        final messageClass = (frame['class'] ?? '').toString().trim();
        final payload = frame['payload'];
        if (id.isNotEmpty &&
            messageClass.isNotEmpty &&
            payload is String) {
          _events.add(
            TransparentUartIncomingMessage(
              messageId: id,
              fromMmId: from,
              messageClass: messageClass,
              payload: payload,
            ),
          );
        }
      case 'ping':
        final nonce = (frame['n'] ?? '').toString().trim();
        if (nonce.isNotEmpty) {
          unawaited(
            _writeFrame(<String, Object?>{
              'v': 1,
              'p': 'MMRP/1',
              'k': 'pong',
              'n': nonce,
              'from': ownMmId,
              'to': from,
            }),
          );
        }
      case 'pong':
        final nonce = (frame['n'] ?? '').toString().trim();
        final pending = _probes.remove(nonce);
        if (pending != null) {
          pending.timer.cancel();
          final elapsed = DateTime.now().difference(pending.started);
          if (!pending.completer.isCompleted) {
            pending.completer.complete(elapsed);
          }
          _events.add(
            TransparentUartProbeResult(
              peerMmId: from,
              rttMillis: elapsed.inMilliseconds,
            ),
          );
        }
    }
  }

  void _emitStats() {
    _events.add(
      TransparentUartStatsEvent(
        txBytes: txBytes,
        rxBytes: rxBytes,
        txFrames: txFrames,
        rxFrames: rxFrames,
        badFrames: badFrames,
      ),
    );
  }

  void _failProbes(Object error) {
    for (final pending in _probes.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _probes.clear();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _failProbes(StateError('LR24 transport closed'));
    await _events.close();
  }
}
