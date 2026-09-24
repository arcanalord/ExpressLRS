import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/delivery.dart';
import '../core/models.dart';

const int meshLanPort = 45841;
const int _maxDatagramBytes = 1200;
const Duration _peerTtl = Duration(seconds: 45);
const Duration _helloInterval = Duration(seconds: 15);
const Duration _ackTimeout = Duration(milliseconds: 2500);

final class LanPeer {
  const LanPeer({
    required this.mmId,
    required this.label,
    required this.address,
    required this.lastSeen,
  });

  final String mmId;
  final String label;
  final String address;
  final DateTime lastSeen;
}

sealed class LanTransportEvent {
  const LanTransportEvent();
}

final class LanStateEvent extends LanTransportEvent {
  const LanStateEvent(this.state, {this.error});
  final String state;
  final String? error;
}

final class LanPeersEvent extends LanTransportEvent {
  const LanPeersEvent(this.peers);
  final List<LanPeer> peers;
}

final class LanIncomingText extends LanTransportEvent {
  const LanIncomingText({
    required this.messageId,
    required this.fromMmId,
    required this.text,
    required this.sourceAddress,
  });
  final String messageId;
  final String fromMmId;
  final String text;
  final String sourceAddress;
}

final class LanIncomingData extends LanTransportEvent {
  const LanIncomingData({
    required this.messageId,
    required this.fromMmId,
    required this.messageClass,
    required this.payload,
    required this.sourceAddress,
  });
  final String messageId;
  final String fromMmId;
  final String messageClass;
  final String payload;
  final String sourceAddress;
}

final class LanDeliveryEvent extends LanTransportEvent {
  const LanDeliveryEvent({
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

final class LanLogEvent extends LanTransportEvent {
  const LanLogEvent(this.message);
  final String message;
}

final class LanProbeEvent extends LanTransportEvent {
  const LanProbeEvent({
    required this.mmId,
    required this.ok,
    this.rttMillis,
    this.detail,
  });

  final String mmId;
  final bool ok;
  final int? rttMillis;
  final String? detail;
}

final class LanUntrustedTextEvent extends LanTransportEvent {
  const LanUntrustedTextEvent({
    required this.fromMmId,
    required this.messageId,
  });

  final String fromMmId;
  final String messageId;
}

final class LanPairingEvent extends LanTransportEvent {
  const LanPairingEvent({
    required this.kind,
    required this.fromMmId,
    required this.payload,
  });

  final String kind;
  final String fromMmId;
  final String payload;
}

final class LanWireMessage {
  const LanWireMessage({
    required this.kind,
    required this.fromMmId,
    this.toMmId,
    this.messageId,
    this.label,
    this.text,
    this.payload,
    this.messageClass,
  });

  final String kind;
  final String fromMmId;
  final String? toMmId;
  final String? messageId;
  final String? label;
  final String? text;
  final String? payload;
  final String? messageClass;
}

/// Small stable LAN/1 wire codec. JSON is intentionally human-readable for the
/// first hardware/software gates; routing, storage and message ownership stay
/// above this transport.
abstract final class LanWireCodec {
  static List<int> discover({
    required String fromMmId,
    required String label,
  }) => _encode({'v': 1, 'kind': 'discover', 'from': fromMmId, 'label': label});

  static List<int> presence({
    required String fromMmId,
    required String toMmId,
    required String label,
  }) => _encode({
    'v': 1,
    'kind': 'presence',
    'from': fromMmId,
    'to': toMmId,
    'label': label,
  });

  // Backward compatibility with v0.1.8 peers.
  static List<int> hello({required String fromMmId, required String label}) =>
      _encode({'v': 1, 'kind': 'hello', 'from': fromMmId, 'label': label});

  static List<int> ping({
    required String probeId,
    required String fromMmId,
    required String toMmId,
  }) => _encode({
    'v': 1,
    'kind': 'ping',
    'id': probeId,
    'from': fromMmId,
    'to': toMmId,
  });

  static List<int> pong({
    required String probeId,
    required String fromMmId,
    required String toMmId,
  }) => _encode({
    'v': 1,
    'kind': 'pong',
    'id': probeId,
    'from': fromMmId,
    'to': toMmId,
  });

  static List<int> text({
    required String messageId,
    required String fromMmId,
    required String toMmId,
    required String text,
  }) => _encode({
    'v': 1,
    'kind': 'text',
    'id': messageId,
    'from': fromMmId,
    'to': toMmId,
    'text': text,
  });

  static List<int> data({
    required String messageId,
    required String fromMmId,
    required String toMmId,
    required String messageClass,
    required String payload,
  }) => _encode({
    'v': 1,
    'kind': 'data',
    'id': messageId,
    'from': fromMmId,
    'to': toMmId,
    'class': messageClass,
    'payload': payload,
  });

  static List<int> ack({
    required String messageId,
    required String fromMmId,
    required String toMmId,
  }) => _encode({
    'v': 1,
    'kind': 'ack',
    'id': messageId,
    'from': fromMmId,
    'to': toMmId,
  });

  static List<int> pairing({
    required String kind,
    required String fromMmId,
    required String toMmId,
    required String payload,
  }) => _encode({
    'v': 1,
    'kind': kind,
    'from': fromMmId,
    'to': toMmId,
    'payload': payload,
  });

  static List<int> _encode(Map<String, Object?> value) {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > _maxDatagramBytes) {
      throw const FormatException('LAN_DATAGRAM_TOO_LARGE');
    }
    return bytes;
  }

  static LanWireMessage? decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > _maxDatagramBytes) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map<String, dynamic> || raw['v'] != 1) return null;
      final kind = raw['kind'];
      final from = raw['from'];
      if (kind is! String || from is! String || !_validId(from)) return null;
      final to = raw['to'];
      final id = raw['id'];
      final label = raw['label'];
      final text = raw['text'];
      final payload = raw['payload'];
      final messageClass = raw['class'];
      if (to != null && (to is! String || !_validId(to))) return null;
      if (id != null && (id is! String || id.isEmpty || id.length > 160)) {
        return null;
      }
      if (label != null && (label is! String || label.length > 80)) return null;
      if (text != null && (text is! String || text.length > 4000)) return null;
      if (payload != null && (payload is! String || payload.length > 900))
        return null;
      if (messageClass != null &&
          (messageClass is! String || messageClass.length > 32))
        return null;
      return LanWireMessage(
        kind: kind,
        fromMmId: from,
        toMmId: to as String?,
        messageId: id as String?,
        label: label as String?,
        text: text as String?,
        payload: payload as String?,
        messageClass: messageClass as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _validId(String value) =>
      value.startsWith('mm:') && value.length >= 6 && value.length <= 96;
}

final class _PendingLanTx {
  _PendingLanTx(this.recipientMmId, this.timer);
  final String recipientMmId;
  final Timer timer;
}

final class _PendingLanProbe {
  _PendingLanProbe(this.mmId, this.startedAt, this.timer);
  final String mmId;
  final DateTime startedAt;
  final Timer timer;
}

/// Direct local-network transport.
/// Discovery uses a small UDP broadcast HELLO; actual text/ACK traffic is
/// unicast to the last observed peer address. It does not create a second queue.
final class LanTransport implements MessageTransport {
  LanTransport({
    required this.ownMmId,
    required this.deviceLabel,
    this.port = meshLanPort,
  });

  final String ownMmId;
  final String deviceLabel;
  final int port;
  final StreamController<LanTransportEvent> _events =
      StreamController.broadcast();
  final Map<String, LanPeer> _peers = {};
  final Map<String, _PendingLanTx> _pending = {};
  final Map<String, _PendingLanProbe> _pendingProbes = {};
  final Set<String> _allowedMmIds = <String>{};

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  Timer? _helloTimer;
  String state = 'offline';
  String? lastError;
  List<String> localAddresses = const [];

  Stream<LanTransportEvent> get events => _events.stream;
  List<LanPeer> get peers {
    final values = _peers.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(values);
  }

  @override
  String get id => 'lan';

  @override
  bool get isAvailable => _socket != null && state == 'ready';

  void setAllowedPeers(Iterable<String> mmIds) {
    _allowedMmIds
      ..clear()
      ..addAll(mmIds.where((id) => id != ownMmId));
  }

  Future<void> start() async {
    if (_socket != null) return;
    _setState('starting');
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _socket = socket;
      _socketSub = socket.listen(
        _onSocketEvent,
        onError: (Object error, StackTrace stack) =>
            _fail('LAN_SOCKET: $error'),
        onDone: () => _handleSocketClosed('LAN_SOCKET_CLOSED'),
      );
      localAddresses = await _findLocalAddresses();
      _setState('ready');
      _log('LAN ready port=$port');
      await announce();
      _helloTimer = Timer.periodic(_helloInterval, (_) {
        unawaited(announce());
        _expirePeers();
      });
    } catch (error) {
      await stop();
      _fail('LAN_START: $error');
      rethrow;
    }
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> stop() async {
    _helloTimer?.cancel();
    _helloTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    for (final pending in _pending.values) {
      pending.timer.cancel();
    }
    _pending.clear();
    for (final pending in _pendingProbes.values) {
      pending.timer.cancel();
    }
    _pendingProbes.clear();
    if (_peers.isNotEmpty) {
      _peers.clear();
      _events.add(const LanPeersEvent([]));
    }
    state = 'offline';
    _events.add(const LanStateEvent('offline'));
  }

  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      final bytes = LanWireCodec.discover(
        fromMmId: ownMmId,
        label: deviceLabel,
      );
      final sent = socket.send(bytes, InternetAddress('255.255.255.255'), port);
      if (sent == 0) _log('DISCOVER send deferred');
      _log('DISCOVER broadcast');
    } catch (error) {
      _fail('LAN_DISCOVER: $error', keepReady: true);
    }
  }

  Future<void> probe(String mmId) async {
    final socket = _socket;
    final peer = _peers[mmId];
    if (socket == null || peer == null || state != 'ready') {
      _events.add(
        LanProbeEvent(mmId: mmId, ok: false, detail: 'LAN_PEER_NOT_FOUND'),
      );
      return;
    }
    final now = DateTime.now().toUtc();
    final probeId = 'p-${now.microsecondsSinceEpoch}';
    final bytes = LanWireCodec.ping(
      probeId: probeId,
      fromMmId: ownMmId,
      toMmId: mmId,
    );
    final written = socket.send(bytes, InternetAddress(peer.address), port);
    if (written != bytes.length) {
      _events.add(
        LanProbeEvent(mmId: mmId, ok: false, detail: 'LAN_PING_BLOCKED'),
      );
      return;
    }
    _pendingProbes.remove(probeId)?.timer.cancel();
    final timer = Timer(const Duration(seconds: 2), () {
      final pending = _pendingProbes.remove(probeId);
      if (pending == null) return;
      _events.add(
        LanProbeEvent(
          mmId: pending.mmId,
          ok: false,
          detail: 'LAN_PING_TIMEOUT',
        ),
      );
      _log('PING timeout ${pending.mmId}');
    });
    _pendingProbes[probeId] = _PendingLanProbe(mmId, now, timer);
    _log('PING $probeId -> ${peer.label} ${peer.address}');
  }

  Future<void> sendPairing({
    required String mmId,
    required String kind,
    required String payload,
  }) async {
    final socket = _socket;
    final peer = _peers[mmId];
    if (socket == null || peer == null || state != 'ready') {
      throw StateError('LAN_PAIR_PEER_NOT_FOUND');
    }
    const allowedKinds = {
      'pair_offer',
      'pair_answer',
      'pair_confirm',
      'pair_cancel',
    };
    if (!allowedKinds.contains(kind)) {
      throw ArgumentError.value(kind, 'kind', 'unsupported pairing kind');
    }
    final bytes = LanWireCodec.pairing(
      kind: kind,
      fromMmId: ownMmId,
      toMmId: mmId,
      payload: payload,
    );
    final written = socket.send(bytes, InternetAddress(peer.address), port);
    if (written != bytes.length) throw StateError('LAN_PAIR_SEND_BLOCKED');
    _log('PAIR $kind -> ${peer.label} ${peer.address}');
  }

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    final socket = _socket;
    if (socket == null || state != 'ready') {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LAN_NOT_READY',
      );
    }
    if (!_allowedMmIds.contains(envelope.recipientMmId)) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LAN_CONTACT_NOT_VERIFIED',
      );
    }
    final peer = _peers[envelope.recipientMmId];
    if (peer == null ||
        DateTime.now().toUtc().difference(peer.lastSeen) > _peerTtl) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LAN_PEER_NOT_FOUND',
      );
    }
    if (envelope.messageClass != 'text' &&
        envelope.messageClass != 'map_point') {
      return const TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'LAN_MESSAGE_CLASS_UNSUPPORTED',
      );
    }
    try {
      final bytes = envelope.messageClass == 'text'
          ? LanWireCodec.text(
              messageId: envelope.messageId,
              fromMmId: ownMmId,
              toMmId: envelope.recipientMmId,
              text: envelope.payload,
            )
          : LanWireCodec.data(
              messageId: envelope.messageId,
              fromMmId: ownMmId,
              toMmId: envelope.recipientMmId,
              messageClass: envelope.messageClass,
              payload: envelope.payload,
            );
      final written = socket.send(bytes, InternetAddress(peer.address), port);
      if (written != bytes.length) {
        return const TransportSendResult(
          TransportSendStatus.rejected,
          detail: 'LAN_SEND_BLOCKED',
        );
      }
      _pending.remove(envelope.messageId)?.timer.cancel();
      final timer = Timer(_ackTimeout, () {
        final pending = _pending.remove(envelope.messageId);
        if (pending == null) return;
        _events.add(
          LanDeliveryEvent(
            messageId: envelope.messageId,
            recipientMmId: pending.recipientMmId,
            ok: false,
            detail: 'LAN_ACK_TIMEOUT',
          ),
        );
        _log('ACK timeout ${envelope.messageId}');
      });
      _pending[envelope.messageId] = _PendingLanTx(
        envelope.recipientMmId,
        timer,
      );
      _log('TX ${envelope.messageId} -> ${peer.label} ${peer.address}');
      return const TransportSendResult(TransportSendStatus.accepted);
    } on FormatException catch (error) {
      return TransportSendResult(
        TransportSendStatus.rejected,
        detail: error.message,
      );
    } catch (error) {
      return TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'LAN_SEND_FAILED: $error',
      );
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      _handleDatagram(datagram!);
    }
  }

  void _handleDatagram(Datagram datagram) {
    final message = LanWireCodec.decode(datagram.data);
    if (message == null || message.fromMmId == ownMmId) return;
    _touchPeer(
      mmId: message.fromMmId,
      label: message.label,
      address: datagram.address.address,
    );

    switch (message.kind) {
      case 'discover':
      case 'hello':
        _sendPresence(datagram.address, toMmId: message.fromMmId);
        return;
      case 'presence':
        if (message.toMmId != ownMmId) return;
        return;
      case 'ping':
        if (message.toMmId != ownMmId || message.messageId == null) return;
        _sendPong(
          datagram.address,
          probeId: message.messageId!,
          toMmId: message.fromMmId,
        );
        return;
      case 'pong':
        if (message.toMmId != ownMmId || message.messageId == null) return;
        final pending = _pendingProbes.remove(message.messageId!);
        if (pending == null || pending.mmId != message.fromMmId) return;
        pending.timer.cancel();
        final rtt = DateTime.now().toUtc().difference(pending.startedAt);
        _events.add(
          LanProbeEvent(
            mmId: pending.mmId,
            ok: true,
            rttMillis: rtt.inMilliseconds,
          ),
        );
        _log(
          'PONG ${message.messageId} <- ${message.fromMmId} ${rtt.inMilliseconds}ms',
        );
        return;
      case 'pair_offer':
      case 'pair_answer':
      case 'pair_confirm':
      case 'pair_cancel':
        if (message.toMmId != ownMmId || message.payload == null) return;
        _events.add(
          LanPairingEvent(
            kind: message.kind,
            fromMmId: message.fromMmId,
            payload: message.payload!,
          ),
        );
        _log('PAIR ${message.kind} <- ${message.fromMmId}');
        return;
      case 'text':
        if (message.toMmId != ownMmId ||
            message.messageId == null ||
            message.text == null) {
          return;
        }
        if (!_allowedMmIds.contains(message.fromMmId)) {
          _events.add(
            LanUntrustedTextEvent(
              fromMmId: message.fromMmId,
              messageId: message.messageId!,
            ),
          );
          _log('BLOCK unpaired ${message.messageId} <- ${message.fromMmId}');
          return;
        }
        _events.add(
          LanIncomingText(
            messageId: message.messageId!,
            fromMmId: message.fromMmId,
            text: message.text!,
            sourceAddress: datagram.address.address,
          ),
        );
        _log('RX ${message.messageId} <- ${message.fromMmId}');
        return;
      case 'data':
        if (message.toMmId != ownMmId ||
            message.messageId == null ||
            message.messageClass == null ||
            message.payload == null) {
          return;
        }
        if (!_allowedMmIds.contains(message.fromMmId)) {
          _events.add(
            LanUntrustedTextEvent(
              fromMmId: message.fromMmId,
              messageId: message.messageId!,
            ),
          );
          _log(
            'BLOCK unpaired data ${message.messageId} <- ${message.fromMmId}',
          );
          return;
        }
        _events.add(
          LanIncomingData(
            messageId: message.messageId!,
            fromMmId: message.fromMmId,
            messageClass: message.messageClass!,
            payload: message.payload!,
            sourceAddress: datagram.address.address,
          ),
        );
        _log(
          'RX ${message.messageClass} ${message.messageId} <- ${message.fromMmId}',
        );
        return;
      case 'ack':
        if (message.toMmId != ownMmId || message.messageId == null) return;
        final pending = _pending.remove(message.messageId!);
        if (pending == null || pending.recipientMmId != message.fromMmId)
          return;
        pending.timer.cancel();
        _events.add(
          LanDeliveryEvent(
            messageId: message.messageId!,
            recipientMmId: pending.recipientMmId,
            ok: true,
          ),
        );
        _log('ACK ${message.messageId} <- ${message.fromMmId}');
        return;
    }
  }

  void _sendPresence(InternetAddress address, {required String toMmId}) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(
        LanWireCodec.presence(
          fromMmId: ownMmId,
          toMmId: toMmId,
          label: deviceLabel,
        ),
        address,
        port,
      );
      _log('PRESENCE -> $toMmId ${address.address}');
    } catch (error) {
      _log('PRESENCE send failed: $error');
    }
  }

  void _sendPong(
    InternetAddress address, {
    required String probeId,
    required String toMmId,
  }) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(
        LanWireCodec.pong(probeId: probeId, fromMmId: ownMmId, toMmId: toMmId),
        address,
        port,
      );
    } catch (error) {
      _log('PONG send failed: $error');
    }
  }

  void acknowledgeIncoming({
    required String sourceAddress,
    required String messageId,
    required String toMmId,
  }) {
    _sendAck(
      InternetAddress(sourceAddress),
      messageId: messageId,
      toMmId: toMmId,
    );
  }

  void _sendAck(
    InternetAddress address, {
    required String messageId,
    required String toMmId,
  }) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(
        LanWireCodec.ack(
          messageId: messageId,
          fromMmId: ownMmId,
          toMmId: toMmId,
        ),
        address,
        port,
      );
    } catch (error) {
      _log('ACK send failed: $error');
    }
  }

  void _touchPeer({
    required String mmId,
    required String? label,
    required String address,
  }) {
    final safeLabel = (label?.trim().isNotEmpty ?? false)
        ? label!.trim()
        : 'Mesh ${mmId.substring(mmId.length - 4).toUpperCase()}';
    final before = _peers[mmId];
    _peers[mmId] = LanPeer(
      mmId: mmId,
      label: safeLabel,
      address: address,
      lastSeen: DateTime.now().toUtc(),
    );
    if (before == null ||
        before.address != address ||
        before.label != safeLabel) {
      _log('PEER $safeLabel $address');
    }
    _events.add(LanPeersEvent(peers));
  }

  void _expirePeers() {
    final now = DateTime.now().toUtc();
    final stale = _peers.entries
        .where((entry) => now.difference(entry.value.lastSeen) > _peerTtl)
        .map((entry) => entry.key)
        .toList();
    if (stale.isEmpty) return;
    for (final id in stale) {
      _peers.remove(id);
    }
    _events.add(LanPeersEvent(peers));
  }

  Future<List<String>> _findLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final result = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) result.add(address.address);
        }
      }
      return result.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  void _setState(String next, {String? error}) {
    state = next;
    lastError = error;
    _events.add(LanStateEvent(next, error: error));
  }

  void _fail(String message, {bool keepReady = false}) {
    lastError = message;
    if (!keepReady) state = 'error';
    _events.add(LanStateEvent(state, error: message));
    _log(message);
  }

  void _handleSocketClosed(String reason) {
    if (_socket == null) return;
    _socket = null;
    state = 'offline';
    lastError = reason;
    _events.add(LanStateEvent('offline', error: reason));
  }

  void _log(String message) => _events.add(LanLogEvent(message));

  Future<void> close() async {
    await stop();
    await _events.close();
  }
}
