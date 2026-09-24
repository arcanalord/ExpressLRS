import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/delivery.dart';
import '../core/models.dart';
import 'android_usb_serial_bridge.dart';

sealed class Ep2TransportEvent {
  const Ep2TransportEvent();
}

final class Ep2StateEvent extends Ep2TransportEvent {
  const Ep2StateEvent(this.state, {this.error});
  final String state;
  final String? error;
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

final class Ep2UartTransport implements MessageTransport {
  Ep2UartTransport({
    required AndroidUsbSerialBridge bridge,
    required int? Function(String mmId) resolvePeerNode,
  }) : _bridge = bridge,
       _resolvePeerNode = resolvePeerNode {
    _subscription = _bridge.events.listen(_onBridgeEvent);
  }

  final AndroidUsbSerialBridge _bridge;
  final int? Function(String mmId) _resolvePeerNode;
  final StreamController<Ep2TransportEvent> _events =
      StreamController.broadcast();
  final Map<int, _PendingEp2Tx> _pending = {};
  StreamSubscription<AndroidUsbSerialEvent>? _subscription;
  String _buffer = '';
  int _nextSequence = 1;
  Timer? _handshakeTimer;

  String state = 'disconnected';
  String? lastError;
  int? localNodeId;
  String? firmwareVersion;
  String? radioState;
  String? profileId;

  Stream<Ep2TransportEvent> get events => _events.stream;

  @override
  String get id => 'ep2-uart';

  @override
  bool get isAvailable => state == 'ready';

  Future<void> connect(int deviceId) async {
    lastError = null;
    state = 'connecting';
    _events.add(const Ep2StateEvent('connecting'));
    await _bridge.connect(deviceId, baudRate: 115200);
  }

  Future<void> disconnect() async {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    await _bridge.disconnect();
    _pending.clear();
    state = 'disconnected';
    _events.add(const Ep2StateEvent('disconnected'));
  }

  Future<void> requestInfo() => _writeLine('INFO');
  Future<void> requestStats() => _writeLine('STATS');
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
    if (_pending.isNotEmpty) {
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
        state = 'handshaking';
        lastError = null;
        _events.add(const Ep2StateEvent('handshaking'));
        _handshakeTimer?.cancel();
        _handshakeTimer = Timer(const Duration(seconds: 3), () {
          if (state != 'handshaking') return;
          state = 'error';
          lastError = 'EP2_PROTOCOL_TIMEOUT: нужна прошивка EP2 LINK v0.2.0';
          _events.add(Ep2StateEvent('error', error: lastError));
        });
        unawaited(requestInfo());
      } else if (next == 'permission') {
        state = 'permission';
        _events.add(const Ep2StateEvent('permission'));
      } else if (next == 'permission_denied' || next == 'error') {
        state = 'error';
        lastError = error ?? next;
        _events.add(Ep2StateEvent('error', error: lastError));
      } else if (next == 'offline' || next == 'disconnected') {
        _handshakeTimer?.cancel();
        _handshakeTimer = null;
        state = 'disconnected';
        _failAll('EP2_UART_DISCONNECTED');
        _events.add(const Ep2StateEvent('disconnected'));
      }
      return;
    }
    if (event is AndroidUsbSerialBytes) {
      _events.add(Ep2RawBytesEvent(Uint8List.fromList(event.bytes)));
      _ingest(event.bytes);
    }
  }

  void _ingest(Uint8List bytes) {
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
          localNodeId = int.tryParse(parts[1]);
          firmwareVersion = parts[2];
          radioState = parts[6];
          profileId = parts[7];
          state = radioState == 'RADIO_OK' ? 'ready' : 'error';
          lastError = state == 'ready' ? null : radioState;
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
      case 'ACK':
        if (parts.length >= 2) {
          final sequence = int.tryParse(parts[1]);
          if (sequence != null) _complete(sequence, ok: true);
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
    if (sequence != null && _pending.containsKey(sequence)) {
      _complete(sequence, ok: false, detail: 'EP2_$code');
      return;
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

  Future<void> close() async {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    await _subscription?.cancel();
    await _events.close();
  }
}
