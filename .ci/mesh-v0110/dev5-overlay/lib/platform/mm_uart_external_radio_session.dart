import 'dart:async';
import 'dart:typed_data';

import 'mm_uart_codec.dart';
import 'radio_capability_contract.dart';

abstract interface class MmUartHostLink {
  Future<void> open();
  Future<void> close();
  Future<void> write(Uint8List bytes);
  void setReceiver(void Function(Uint8List bytes) receiver);
  void setDisconnectHandler(void Function(String reason) handler);
  Map<String, Object?>? describe();
}

sealed class ExternalRadioSessionEvent {
  const ExternalRadioSessionEvent();
}

final class ExternalRadioStateEvent extends ExternalRadioSessionEvent {
  const ExternalRadioStateEvent(this.state, {this.reason});
  final String state;
  final String? reason;
}

final class ExternalRadioCapabilitiesEvent extends ExternalRadioSessionEvent {
  const ExternalRadioCapabilitiesEvent(this.info, this.capabilities);
  final RadioInfo info;
  final RadioCapabilities capabilities;
}

final class ExternalRadioPacketEvent extends ExternalRadioSessionEvent {
  const ExternalRadioPacketEvent(this.packet);
  final Map<String, dynamic> packet;
}

final class ExternalRadioTxAcceptedEvent extends ExternalRadioSessionEvent {
  const ExternalRadioTxAcceptedEvent(this.tx);
  final Map<String, dynamic> tx;
}

final class ExternalRadioTxResultEvent extends ExternalRadioSessionEvent {
  const ExternalRadioTxResultEvent(this.tx);
  final Map<String, dynamic> tx;
}

final class ExternalRadioStatsEvent extends ExternalRadioSessionEvent {
  const ExternalRadioStatsEvent(this.stats);
  final Map<String, dynamic> stats;
}

final class ExternalRadioDeviceResetEvent extends ExternalRadioSessionEvent {
  const ExternalRadioDeviceResetEvent(this.payload);
  final Map<String, dynamic> payload;
}

final class ExternalRadioErrorEvent extends ExternalRadioSessionEvent {
  const ExternalRadioErrorEvent(this.error);
  final String error;
}

final class ExternalRadioSessionSnapshot {
  const ExternalRadioSessionSnapshot({
    required this.state,
    this.info,
    this.capabilities,
    this.stats,
    this.bootId,
    this.lastError,
    this.hostLink,
  });

  final String state;
  final RadioInfo? info;
  final RadioCapabilities? capabilities;
  final Map<String, dynamic>? stats;
  final String? bootId;
  final String? lastError;
  final Map<String, Object?>? hostLink;
}

final class _PendingRequest {
  _PendingRequest(this.completer, this.timer);
  final Completer<Object?> completer;
  final Timer timer;
}

final class MmUartExternalRadioSession {
  MmUartExternalRadioSession({
    this.requestTimeout = const Duration(seconds: 1),
  }) {
    _decoder = MmUartFrameStreamDecoder(
      onFrame: _handleFrame,
      onError: (error) => _emitError(error),
    );
  }

  final Duration requestTimeout;
  final StreamController<ExternalRadioSessionEvent> _events =
      StreamController.broadcast();
  final Map<int, _PendingRequest> _pending = {};
  late final MmUartFrameStreamDecoder _decoder;

  MmUartHostLink? _link;
  int _sequence = 1;
  int _recoveryGeneration = 0;
  bool _recovering = false;

  String state = 'offline';
  RadioInfo? info;
  RadioCapabilities? capabilities;
  Map<String, dynamic>? stats;
  String? bootId;
  String? lastError;

  Stream<ExternalRadioSessionEvent> get events => _events.stream;

  ExternalRadioSessionSnapshot snapshot() => ExternalRadioSessionSnapshot(
    state: state,
    info: info,
    capabilities: capabilities,
    stats: stats,
    bootId: bootId,
    lastError: lastError,
    hostLink: _link?.describe(),
  );

  int _nextSequence() {
    final current = _sequence;
    _sequence = (_sequence + 1) & 0xffff;
    if (_sequence == 0) _sequence = 1;
    return current;
  }

  void _setState(String value, {String? reason}) {
    state = value;
    _events.add(ExternalRadioStateEvent(value, reason: reason));
  }

  void _emitError(Object error) {
    final message = error is FormatException
        ? error.message
        : error.toString().replaceFirst('Exception: ', '');
    lastError = message;
    _events.add(ExternalRadioErrorEvent(message));
  }

  Future<ExternalRadioSessionSnapshot> connect(MmUartHostLink link) async {
    if (_link != null && !identical(_link, link)) await disconnect();
    _link = link;
    _decoder.reset();
    link.setReceiver(_decoder.push);
    link.setDisconnectHandler((reason) => _handleDisconnect(reason));
    _setState('connecting');
    await link.open();
    try {
      await _handshake();
      return snapshot();
    } catch (error) {
      _rejectPending(error);
      _decoder.reset();
      _link = null;
      try {
        await link.close();
      } catch (_) {}
      _setState('error');
      _emitError(error);
      rethrow;
    }
  }

  Future<void> _handshake() async {
    final hello = _asMap(
      await request(MmUartFrameType.hello, {
        'host': 'mesh-messenger-flutter',
        'protocol': 1,
      }),
    );
    bootId = _stringOrNull(hello?['bootId']);
    await refreshInfoAndCapabilities();
  }

  Future<ExternalRadioSessionSnapshot> refreshInfoAndCapabilities() async {
    if (_link == null) throw StateError('NO_HOST_LINK');

    final rawInfo = _asMap(await request(MmUartFrameType.getInfo)) ?? const {};
    info = RadioInfo.fromJson(rawInfo, bootId: bootId);

    final rawCaps = _asMap(await request(MmUartFrameType.getCaps)) ?? const {};
    capabilities = RadioCapabilities.fromJson(rawCaps, info: info);
    _events.add(ExternalRadioCapabilitiesEvent(info!, capabilities!));

    final rawState =
        _asMap(await request(MmUartFrameType.getState)) ?? const {};
    final ready = rawState['ready'] == true;
    _setState(
      ready ? 'ready' : (_stringOrNull(rawState['state']) ?? 'connected'),
    );
    return snapshot();
  }

  Future<void> disconnect() async {
    final link = _link;
    _link = null;
    _recoveryGeneration++;
    _recovering = false;
    _rejectPending(StateError('DISCONNECTED'));
    _decoder.reset();
    _setState('offline');
    if (link != null) await link.close();
  }

  void _handleDisconnect(String reason) {
    _rejectPending(StateError(reason));
    _setState('offline', reason: reason);
  }

  void _rejectPending(Object error) {
    for (final item in _pending.values) {
      item.timer.cancel();
      if (!item.completer.isCompleted) item.completer.completeError(error);
    }
    _pending.clear();
  }

  Future<Object?> request(
    int type, [
    Object? payload,
    Duration? timeout,
  ]) async {
    final link = _link;
    if (link == null) throw StateError('NO_HOST_LINK');
    final sequence = _nextSequence();
    final completer = Completer<Object?>();
    final timer = Timer(timeout ?? requestTimeout, () {
      final request = _pending.remove(sequence);
      if (request != null && !request.completer.isCompleted) {
        request.completer.completeError(TimeoutException('REQUEST_TIMEOUT'));
      }
    });
    _pending[sequence] = _PendingRequest(completer, timer);
    try {
      await link.write(
        mmUartEncodeFrame(type: type, sequence: sequence, payload: payload),
      );
    } catch (error) {
      final request = _pending.remove(sequence);
      request?.timer.cancel();
      rethrow;
    }
    return completer.future;
  }

  bool supports(String feature) => capabilities?.supports(feature) == true;
  bool get supportsMmrp => capabilities?.supportsMmrp == true;

  Future<Object?> setProfile(String profileId) {
    final supported = capabilities?.profileIds ?? const [];
    if (supported.isNotEmpty && !supported.contains(profileId)) {
      throw StateError('UNSUPPORTED_PROFILE');
    }
    return request(MmUartFrameType.setProfile, {'profileId': profileId});
  }

  Future<Object?> send({
    required String messageId,
    required Object recipientBinding,
    required Object payload,
    required String payloadType,
    String qos = 'normal',
  }) {
    if (messageId.trim().isEmpty) throw ArgumentError('MESSAGE_ID_REQUIRED');
    if ('$recipientBinding'.trim().isEmpty) {
      throw ArgumentError('RECIPIENT_REQUIRED');
    }
    return request(MmUartFrameType.send, {
      'messageId': messageId,
      'recipientBinding': recipientBinding,
      'payload': payload,
      'payloadType': payloadType,
      'qos': qos,
    });
  }

  Future<Map<String, dynamic>> refreshStats() async {
    stats =
        _asMap(await request(MmUartFrameType.getStats)) ?? <String, dynamic>{};
    return stats!;
  }

  Future<Map<String, dynamic>> compatSelftest() async {
    return _asMap(await request(MmUartFrameType.compatSelftest)) ??
        <String, dynamic>{};
  }

  Future<Map<String, dynamic>> enterOta() async {
    return _asMap(await request(MmUartFrameType.enterOta)) ??
        <String, dynamic>{};
  }

  Future<Map<String, dynamic>> exitOta() async {
    return _asMap(await request(MmUartFrameType.exitOta)) ??
        <String, dynamic>{};
  }

  Future<void> reboot() async {
    await request(MmUartFrameType.reboot);
  }

  Future<void> _recoverAfterReset(int generation) async {
    if (_recovering || _link == null || generation != _recoveryGeneration)
      return;
    _recovering = true;
    try {
      await _handshake();
    } catch (error) {
      if (generation == _recoveryGeneration) {
        _setState('error', reason: 'deviceResetRecoveryFailed');
        _emitError(error);
      }
    } finally {
      if (generation == _recoveryGeneration) _recovering = false;
    }
  }

  void _handleFrame(MmUartFrame frame) {
    Object? decoded;
    try {
      decoded = frame.decodeJsonPayload();
    } catch (error) {
      _emitError(error);
      return;
    }

    if (frame.type == MmUartFrameType.response) {
      final pending = _pending.remove(frame.sequence);
      if (pending == null) return;
      pending.timer.cancel();
      final payload = _asMap(decoded);
      if (payload?['ok'] == false) {
        pending.completer.completeError(
          StateError(_stringOrNull(payload?['error']) ?? 'REMOTE_ERROR'),
        );
      } else {
        pending.completer.complete(payload?['data']);
      }
      return;
    }

    final payload = _asMap(decoded) ?? <String, dynamic>{};
    switch (frame.type) {
      case MmUartFrameType.ready:
        _setState('ready');
      case MmUartFrameType.stateChanged:
        _setState(_stringOrNull(payload['state']) ?? 'connected');
      case MmUartFrameType.linkStats:
        stats = payload;
        _events.add(ExternalRadioStatsEvent(payload));
      case MmUartFrameType.rxPacket:
        _events.add(ExternalRadioPacketEvent(payload));
      case MmUartFrameType.txAccepted:
        _events.add(ExternalRadioTxAcceptedEvent(payload));
      case MmUartFrameType.txResult:
        _events.add(ExternalRadioTxResultEvent(payload));
      case MmUartFrameType.deviceReset:
        bootId = _stringOrNull(payload['bootId']);
        info = null;
        capabilities = null;
        final generation = ++_recoveryGeneration;
        _setState('connecting', reason: 'deviceReset');
        _events.add(ExternalRadioDeviceResetEvent(payload));
        scheduleMicrotask(() => _recoverAfterReset(generation));
      case MmUartFrameType.radioError:
        _emitError(_stringOrNull(payload['error']) ?? 'REMOTE_RADIO_ERROR');
    }
  }

  Future<void> close() async {
    await disconnect();
    await _events.close();
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final clean = '$value'.trim();
  return clean.isEmpty ? null : clean;
}
