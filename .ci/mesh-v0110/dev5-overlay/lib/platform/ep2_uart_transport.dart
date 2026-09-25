import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/delivery.dart';
import '../core/models.dart';
import 'android_usb_serial_bridge.dart';
import 'radio_uart_probe.dart';

enum RadioUartProtocol { unknown, ep2Link, crsf }

sealed class Ep2TransportEvent {
  const Ep2TransportEvent();
}

final class Ep2StateEvent extends Ep2TransportEvent {
  const Ep2StateEvent(this.state, {this.error});
  final String state;
  final String? error;
}

final class Ep2ProbeEvent extends Ep2TransportEvent {
  const Ep2ProbeEvent({
    required this.protocol,
    required this.baudRate,
    this.detail,
  });

  final RadioUartProtocol protocol;
  final int baudRate;
  final String? detail;
}

final class Ep2InfoEvent extends Ep2TransportEvent {
  const Ep2InfoEvent({
    required this.nodeId,
    required this.firmware,
    required this.radioState,
    required this.profile,
  });
  final int nodeId;
  final String firmware;
  final String radioState;
  final String profile;
}

final class Ep2StatsEvent extends Ep2TransportEvent {
  const Ep2StatsEvent({
    this.rssi10,
    this.snr10,
    this.rttMs,
    this.tx,
    this.rx,
    this.loss,
    this.crcErrors,
    this.txErrors,
    this.retries,
    this.duplicates,
  });

  final int? rssi10;
  final int? snr10;
  final int? rttMs;
  final int? tx;
  final int? rx;
  final int? loss;
  final int? crcErrors;
  final int? txErrors;
  final int? retries;
  final int? duplicates;
}

final class Ep2DeliveryEvent extends Ep2TransportEvent {
  const Ep2DeliveryEvent({
    required this.messageId,
    required this.recipientMmId,
    required this.ok,
    this.detail,
  });
  final String messageId;
  final String recipientMmId;
  final bool ok;
  final String? detail;
}

final class Ep2IncomingText extends Ep2TransportEvent {
  const Ep2IncomingText({
    required this.fromNode,
    required this.sequence,
    required this.text,
  });
  final int fromNode;
  final int sequence;
  final String text;
}

final class Ep2RawBytesEvent extends Ep2TransportEvent {
  const Ep2RawBytesEvent(this.bytes);
  final Uint8List bytes;
}

final class Ep2OtaReadyEvent extends Ep2TransportEvent {
  const Ep2OtaReadyEvent({
    required this.ssid,
    required this.password,
    required this.url,
  });
  final String ssid;
  final String password;
  final String url;
}

final class Ep2LogEvent extends Ep2TransportEvent {
  const Ep2LogEvent(this.line);
  final String line;
}

final class _PendingEp2Tx {
  const _PendingEp2Tx(this.messageId, this.recipientMmId);
  final String messageId;
  final String recipientMmId;
}

final class _PendingPing {
  _PendingPing(this.started, this.completer, this.timer);
  final DateTime started;
  final Completer<Duration> completer;
  final Timer timer;
}

final class Ep2UartTransport implements MessageTransport {
  Ep2UartTransport({
    required AndroidUsbSerialBridge bridge,
    required int? Function(String mmId) resolvePeerNode,
  }) : _bridge = bridge,
       _resolvePeerNode = resolvePeerNode {
    _subscription = _bridge.events.listen(_onBridgeEvent);
  }

  static const int ep2Baud = 115200;
  static const int crsfBaud = 420000;

  final AndroidUsbSerialBridge _bridge;
  final int? Function(String mmId) _resolvePeerNode;
  final StreamController<Ep2TransportEvent> _events =
      StreamController.broadcast();
  final Map<int, _PendingEp2Tx> _pending = {};
  final Map<int, _PendingPing> _pendingPings = {};
  final List<int> _binaryBuffer = <int>[];
  StreamSubscription<AndroidUsbSerialEvent>? _subscription;
  String _buffer = '';
  int _nextSequence = 1;
  Timer? _handshakeTimer;
  Timer? _probeTimer;
  Timer? _ep2InfoRetryTimer;
  int? _probeDeviceId;
  String _probeStage = 'none';

  String state = 'disconnected';
  String? lastError;
  int? localNodeId;
  String? firmwareVersion;
  String? radioState;
  String? profileId;
  RadioUartProtocol protocol = RadioUartProtocol.unknown;
  int? currentBaud;

  int? rssi10;
  int? snr10;
  int? rttMs;
  int? txCount;
  int? rxCount;
  int? lossCount;
  int? crcErrors;
  int? txErrors;
  int? retryCount;
  int? duplicateCount;

  Stream<Ep2TransportEvent> get events => _events.stream;

  @override
  String get id => 'ep2-uart';

  @override
  bool get isAvailable =>
      state == 'ready' && protocol == RadioUartProtocol.ep2Link;

  Future<void> connect(int deviceId) async {
    await _beginEp2Probe(deviceId, allowCrsfFallback: false);
  }

  Future<void> connectAuto(int deviceId) async {
    await _beginEp2Probe(deviceId, allowCrsfFallback: true);
  }

  Future<void> _beginEp2Probe(
    int deviceId, {
    required bool allowCrsfFallback,
  }) async {
    _cancelProbeTimers();
    _clearRuntimeSnapshot();
    _probeDeviceId = deviceId;
    _probeStage = allowCrsfFallback ? 'ep2-auto' : 'ep2-direct';
    protocol = RadioUartProtocol.unknown;
    currentBaud = ep2Baud;
    lastError = null;
    _buffer = '';
    _binaryBuffer.clear();
    state = 'connecting';
    _events.add(const Ep2StateEvent('connecting'));
    _events.add(
      const Ep2ProbeEvent(
        protocol: RadioUartProtocol.unknown,
        baudRate: ep2Baud,
        detail: 'Проверяем EP2 LINK',
      ),
    );
    await _bridge.connect(deviceId, baudRate: ep2Baud);
  }

  Future<void> _switchToCrsfProbe() async {
    final deviceId = _probeDeviceId;
    if (deviceId == null || _probeStage != 'ep2-auto') return;
    _probeStage = 'switching';
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _buffer = '';
    _binaryBuffer.clear();
    protocol = RadioUartProtocol.unknown;
    currentBaud = crsfBaud;
    state = 'probing';
    _events.add(
      const Ep2ProbeEvent(
        protocol: RadioUartProtocol.unknown,
        baudRate: crsfBaud,
        detail: 'EP2 LINK не найден, проверяем ELRS/CRSF',
      ),
    );
    await _bridge.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_probeDeviceId != deviceId) return;
    _probeStage = 'crsf';
    await _bridge.connect(deviceId, baudRate: crsfBaud);
  }

  Future<void> disconnect() async {
    _cancelProbeTimers();
    _probeDeviceId = null;
    _probeStage = 'none';
    await _bridge.disconnect();
    _pending.clear();
    _failPings(StateError('USB radio disconnected'));
    _buffer = '';
    _binaryBuffer.clear();
    _clearRuntimeSnapshot();
    state = 'disconnected';
    protocol = RadioUartProtocol.unknown;
    currentBaud = null;
    _events.add(const Ep2StateEvent('disconnected'));
  }

  Future<void> requestInfo() => _writeLine('INFO');
  Future<void> requestStats() => _writeLine('STATS');

  Future<Duration> ping(int targetNode) async {
    if (!isAvailable) {
      throw StateError('Радиомодуль не готов');
    }
    if (targetNode < 1 || targetNode > 15 || targetNode == localNodeId) {
      throw ArgumentError.value(
        targetNode,
        'targetNode',
        'Неверный номер узла',
      );
    }
    if (_pending.isNotEmpty || _pendingPings.isNotEmpty) {
      throw StateError('Радиомодуль занят');
    }

    final sequence = _allocateSequence();
    final completer = Completer<Duration>();
    late final Timer timer;
    timer = Timer(const Duration(seconds: 6), () {
      final pending = _pendingPings.remove(sequence);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          TimeoutException('PING timeout', const Duration(seconds: 6)),
        );
      }
    });
    _pendingPings[sequence] = _PendingPing(DateTime.now(), completer, timer);
    try {
      await _writeLine('CMD,$sequence,PING,$targetNode');
    } catch (error, stackTrace) {
      final pending = _pendingPings.remove(sequence);
      pending?.timer.cancel();
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }
  Future<void> startWifiUpdate() => _writeLine('WIFI_UPDATE');

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    if (!isAvailable) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'EP2_UART_NOT_READY',
      );
    }
    final peerNode = _resolvePeerNode(envelope.recipientMmId);
    if (peerNode == null || peerNode < 1 || peerNode > 15) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'EP2_NODE_NOT_BOUND',
      );
    }
    if (envelope.messageClass != 'text') {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'EP2_MESSAGE_CLASS_UNSUPPORTED',
      );
    }
    if (_pending.isNotEmpty || _pendingPings.isNotEmpty) {
      return const TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'EP2_BUSY',
      );
    }

    final sequence = _allocateSequence();
    final encodedText = base64Url
        .encode(utf8.encode(envelope.payload))
        .replaceAll('=', '');
    _pending[sequence] = _PendingEp2Tx(
      envelope.messageId,
      envelope.recipientMmId,
    );
    try {
      await _writeLine('CMD,$sequence,SEND_TEXT,$peerNode,$encodedText');
      return const TransportSendResult(TransportSendStatus.accepted);
    } catch (error) {
      _pending.remove(sequence);
      return TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'EP2_UART_WRITE_FAILED: $error',
      );
    }
  }

  int _allocateSequence() {
    final current = _nextSequence;
    _nextSequence++;
    if (_nextSequence > 0x7fffffff) _nextSequence = 1;
    return current;
  }

  Future<void> _writeLine(String line) =>
      _bridge.write(Uint8List.fromList(utf8.encode('$line\n')));

  void _onBridgeEvent(AndroidUsbSerialEvent event) {
    if (event is AndroidUsbSerialState) {
      final next = event.status['state'] as String? ?? 'unknown';
      final error = event.status['error'] as String?;
      if (next == 'ready') {
        lastError = null;
        if (_probeStage == 'crsf') {
          state = 'probing';
          _events.add(const Ep2StateEvent('probing'));
          _probeTimer?.cancel();
          _probeTimer = Timer(const Duration(seconds: 2), () {
            if (_probeStage != 'crsf' ||
                protocol != RadioUartProtocol.unknown) {
              return;
            }
            _probeStage = 'done';
            state = 'unknown';
            lastError = 'UART_PROTOCOL_UNKNOWN';
            _events.add(
              const Ep2ProbeEvent(
                protocol: RadioUartProtocol.unknown,
                baudRate: crsfBaud,
                detail: 'Протокол не определён',
              ),
            );
            _events.add(Ep2StateEvent('unknown', error: lastError));
          });
        } else {
          state = 'handshaking';
          _events.add(const Ep2StateEvent('handshaking'));
          _handshakeTimer?.cancel();
          _ep2InfoRetryTimer?.cancel();
          final autoFallback = _probeStage == 'ep2-auto';
          _handshakeTimer = Timer(const Duration(milliseconds: 4200), () {
            if (state != 'handshaking') return;
            if (autoFallback) {
              unawaited(_switchToCrsfProbe());
            } else {
              state = 'error';
              lastError = 'EP2_PROTOCOL_TIMEOUT';
              _events.add(Ep2StateEvent('error', error: lastError));
            }
          });
          unawaited(requestInfo());
          var retries = 0;
          _ep2InfoRetryTimer = Timer.periodic(
            const Duration(milliseconds: 900),
            (timer) {
              if (state != 'handshaking' ||
                  !(_probeStage == 'ep2-auto' ||
                      _probeStage == 'ep2-direct')) {
                timer.cancel();
                return;
              }
              retries++;
              unawaited(requestInfo());
              if (retries >= 3) timer.cancel();
            },
          );
        }
      } else if (next == 'permission') {
        state = 'permission';
        _events.add(const Ep2StateEvent('permission'));
      } else if (next == 'permission_denied' || next == 'error') {
        state = 'error';
        lastError = error ?? next;
        _events.add(Ep2StateEvent('error', error: lastError));
      } else if (next == 'offline' || next == 'disconnected') {
        if (_probeStage == 'switching') return;
        _cancelProbeTimers();
        state = 'disconnected';
        _failAll('EP2_UART_DISCONNECTED');
        _failPings(StateError('USB radio disconnected'));
        _events.add(const Ep2StateEvent('disconnected'));
      }
      return;
    }
    if (event is AndroidUsbSerialBytes) {
      _events.add(Ep2RawBytesEvent(Uint8List.fromList(event.bytes)));
      if (_probeStage == 'crsf') {
        _ingestCrsf(event.bytes);
      } else {
        _ingestAscii(event.bytes);
      }
    }
  }

  void _ingestAscii(Uint8List bytes) {
    _buffer += utf8.decode(bytes, allowMalformed: true).replaceAll('\r', '');
    if (_buffer.length > 8192 && !_buffer.contains('\n')) {
      _buffer = '';
      lastError = 'EP2_PROTOCOL_INVALID_STREAM';
      _events.add(Ep2StateEvent(state, error: lastError));
      return;
    }
    while (true) {
      final newline = _buffer.indexOf('\n');
      if (newline < 0) break;
      final line = _buffer.substring(0, newline).trim();
      _buffer = _buffer.substring(newline + 1);
      if (line.isNotEmpty) _handleLine(line);
    }
  }

  void _ingestCrsf(Uint8List bytes) {
    _binaryBuffer.addAll(bytes);
    if (_binaryBuffer.length > 512) {
      _binaryBuffer.removeRange(0, _binaryBuffer.length - 512);
    }
    if (!CrsfFrameDetector.containsValidFrame(_binaryBuffer)) return;

    _probeTimer?.cancel();
    _probeTimer = null;
    _probeStage = 'done';
    protocol = RadioUartProtocol.crsf;
    currentBaud = crsfBaud;
    state = 'crsf';
    lastError = null;
    _events.add(
      const Ep2ProbeEvent(
        protocol: RadioUartProtocol.crsf,
        baudRate: crsfBaud,
        detail: 'Обнаружен ELRS / CRSF',
      ),
    );
    _events.add(const Ep2StateEvent('crsf'));
  }

  void _handleLine(String line) {
    _events.add(Ep2LogEvent(line));
    final parts = line.split(',');
    if (parts.isEmpty) return;

    switch (parts[0]) {
      case 'READY':
        if (parts.length >= 3) {
          localNodeId = int.tryParse(parts[1]);
          firmwareVersion = parts[2];
          state = 'handshaking';
          _events.add(const Ep2StateEvent('handshaking'));
          unawaited(requestInfo());
        }
      case 'INFO':
        if (parts.length >= 8) {
          _handshakeTimer?.cancel();
          _handshakeTimer = null;
          _ep2InfoRetryTimer?.cancel();
          _ep2InfoRetryTimer = null;
          _probeTimer?.cancel();
          _probeTimer = null;
          _probeStage = 'done';
          protocol = RadioUartProtocol.ep2Link;
          currentBaud = ep2Baud;
          localNodeId = int.tryParse(parts[1]);
          firmwareVersion = parts[2];
          radioState = parts[6];
          profileId = parts[7];
          state = radioState == 'RADIO_OK' ? 'ready' : 'error';
          lastError = state == 'ready' ? null : radioState;
          _events.add(
            const Ep2ProbeEvent(
              protocol: RadioUartProtocol.ep2Link,
              baudRate: ep2Baud,
              detail: 'EP2 LINK',
            ),
          );
          _events.add(
            Ep2InfoEvent(
              nodeId: localNodeId ?? 0,
              firmware: firmwareVersion ?? '',
              radioState: radioState ?? '',
              profile: profileId ?? '',
            ),
          );
          _events.add(Ep2StateEvent(state, error: lastError));
        }
      case 'LINK':
        if (parts.length >= 7) {
          rssi10 = int.tryParse(parts[1]);
          snr10 = int.tryParse(parts[2]);
          rttMs = int.tryParse(parts[3]);
          txCount = int.tryParse(parts[4]);
          rxCount = int.tryParse(parts[5]);
          lossCount = int.tryParse(parts[6]);
          _emitStats();
        }
      case 'RADIO_STATS':
        if (parts.length >= 5) {
          crcErrors = int.tryParse(parts[1]);
          txErrors = int.tryParse(parts[2]);
          retryCount = int.tryParse(parts[3]);
          duplicateCount = int.tryParse(parts[4]);
          _emitStats();
        }
      case 'ACK':
        if (parts.length >= 2) {
          final sequence = int.tryParse(parts[1]);
          if (sequence != null) {
            final ping = _pendingPings.remove(sequence);
            if (ping != null) {
              ping.timer.cancel();
              if (!ping.completer.isCompleted) {
                ping.completer.complete(
                  DateTime.now().difference(ping.started),
                );
              }
              unawaited(requestStats());
            } else {
              _complete(sequence, ok: true);
            }
          }
        }
      case 'RX_TEXT':
        if (parts.length >= 4) {
          final fromNode = int.tryParse(parts[1]);
          final sequence = int.tryParse(parts[2]);
          if (fromNode == null || sequence == null) return;
          final text = _decodeText(parts.sublist(3).join(','));
          _events.add(
            Ep2IncomingText(fromNode: fromNode, sequence: sequence, text: text),
          );
        }
      case 'OTA':
        if (parts.length >= 5 && parts[1] == 'READY') {
          _events.add(
            Ep2OtaReadyEvent(
              ssid: parts[2],
              password: parts[3],
              url: parts.sublist(4).join(','),
            ),
          );
        }
      case 'ERR':
        _handleError(parts);
    }
  }

  void _emitStats() {
    _events.add(
      Ep2StatsEvent(
        rssi10: rssi10,
        snr10: snr10,
        rttMs: rttMs,
        tx: txCount,
        rx: rxCount,
        loss: lossCount,
        crcErrors: crcErrors,
        txErrors: txErrors,
        retries: retryCount,
        duplicates: duplicateCount,
      ),
    );
  }

  String _decodeText(String encoded) {
    try {
      var normalized = encoded.trim();
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      return utf8.decode(base64Url.decode(normalized), allowMalformed: true);
    } catch (_) {
      return encoded;
    }
  }

  void _handleError(List<String> parts) {
    final code = parts.length > 1 ? parts[1] : 'UNKNOWN';
    int? sequence;
    if (parts.length > 2) sequence = int.tryParse(parts.last);
    if (sequence != null) {
      final ping = _pendingPings.remove(sequence);
      if (ping != null) {
        ping.timer.cancel();
        if (!ping.completer.isCompleted) {
          ping.completer.completeError(StateError('EP2_$code'));
        }
        return;
      }
      if (_pending.containsKey(sequence)) {
        _complete(sequence, ok: false, detail: 'EP2_$code');
        return;
      }
    }
    if (_pending.length == 1 &&
        {
          'RADIO_NOT_READY',
          'SEND_FAILED',
          'TIMEOUT',
          'BUSY',
          'BAD_DST',
          'EMPTY_TEXT',
          'UNKNOWN_CMD',
          'RF_PACKET_TOO_LONG',
        }.contains(code)) {
      _complete(_pending.keys.single, ok: false, detail: 'EP2_$code');
      return;
    }
    lastError = 'EP2_$code';
    _events.add(Ep2StateEvent(state, error: lastError));
  }

  void _complete(int sequence, {required bool ok, String? detail}) {
    final pending = _pending.remove(sequence);
    if (pending == null) return;
    _events.add(
      Ep2DeliveryEvent(
        messageId: pending.messageId,
        recipientMmId: pending.recipientMmId,
        ok: ok,
        detail: detail,
      ),
    );
  }

  void _failAll(String detail) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final item in pending) {
      _events.add(
        Ep2DeliveryEvent(
          messageId: item.messageId,
          recipientMmId: item.recipientMmId,
          ok: false,
          detail: detail,
        ),
      );
    }
  }

  void _failPings(Object error) {
    final pending = _pendingPings.values.toList(growable: false);
    _pendingPings.clear();
    for (final ping in pending) {
      ping.timer.cancel();
      if (!ping.completer.isCompleted) ping.completer.completeError(error);
    }
  }

  void _clearRuntimeSnapshot() {
    localNodeId = null;
    firmwareVersion = null;
    radioState = null;
    profileId = null;
    rssi10 = null;
    snr10 = null;
    rttMs = null;
    txCount = null;
    rxCount = null;
    lossCount = null;
    crcErrors = null;
    txErrors = null;
    retryCount = null;
    duplicateCount = null;
  }

  void _cancelProbeTimers() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
    _ep2InfoRetryTimer?.cancel();
    _ep2InfoRetryTimer = null;
  }

  Future<void> close() async {
    _cancelProbeTimers();
    _failPings(StateError('transport closed'));
    await _subscription?.cancel();
    await _events.close();
  }
}
