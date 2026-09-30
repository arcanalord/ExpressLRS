import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'lr24_serial_adapter.dart';

sealed class Mmrp1ControlFrame {
  const Mmrp1ControlFrame({required this.from, required this.to});
  final String from;
  final String to;
}

final class Mmrp1Hello extends Mmrp1ControlFrame {
  const Mmrp1Hello({
    required super.from,
    required super.to,
    required this.label,
    required this.capabilities,
    required this.reply,
  });
  final String label;
  final List<String> capabilities;
  final bool reply;
}

final class Mmrp1Ping extends Mmrp1ControlFrame {
  const Mmrp1Ping({
    required super.from,
    required super.to,
    required this.nonce,
    required this.pong,
  });
  final String nonce;
  final bool pong;
}

final class Mmrp1ControlCodec {
  static const String protocol = 'MMRP/1';

  Uint8List encode(Mmrp1ControlFrame frame) {
    final map = switch (frame) {
      Mmrp1Hello() => <String, Object?>{
          'v': 1,
          'p': protocol,
          'k': frame.reply ? 'hello_reply' : 'hello',
          'from': frame.from,
          'to': frame.to,
          'label': frame.label,
          'caps': frame.capabilities,
        },
      Mmrp1Ping() => <String, Object?>{
          'v': 1,
          'p': protocol,
          'k': frame.pong ? 'pong' : 'ping',
          'n': frame.nonce,
          'from': frame.from,
          'to': frame.to,
        },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  Mmrp1ControlFrame? decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 2048) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    if (map['v'] != 1 || map['p'] != protocol) return null;

    final from = '${map['from'] ?? ''}'.trim();
    final to = '${map['to'] ?? ''}'.trim();
    if (from.isEmpty || to.isEmpty) return null;

    final kind = '${map['k'] ?? ''}';
    if (kind == 'hello' || kind == 'hello_reply') {
      return Mmrp1Hello(
        from: from,
        to: to,
        label: '${map['label'] ?? ''}',
        capabilities: map['caps'] is List
            ? (map['caps'] as List).map((e) => '$e').toList()
            : const <String>[],
        reply: kind == 'hello_reply',
      );
    }
    if (kind == 'ping' || kind == 'pong') {
      final nonce = '${map['n'] ?? ''}'.trim();
      if (nonce.isEmpty) return null;
      return Mmrp1Ping(
        from: from,
        to: to,
        nonce: nonce,
        pong: kind == 'pong',
      );
    }
    return null;
  }
}

sealed class Mmrp1LinkEvent {
  const Mmrp1LinkEvent();
}

final class Mmrp1PeerReady extends Mmrp1LinkEvent {
  const Mmrp1PeerReady({required this.mmId, required this.label});
  final String mmId;
  final String label;
}

final class Mmrp1ProbeResult extends Mmrp1LinkEvent {
  const Mmrp1ProbeResult({required this.mmId, required this.rttMs});
  final String mmId;
  final int rttMs;
}

final class Mmrp1ControlSession {
  Mmrp1ControlSession({
    required this.transport,
    required this.ownMmId,
    required this.ownLabel,
  }) {
    transport.setControlHandler(_handleInbound);
  }

  final Lr24SerialAdapter transport;
  final String ownMmId;
  final String ownLabel;
  final Mmrp1ControlCodec _codec = Mmrp1ControlCodec();
  final StreamController<Mmrp1LinkEvent> _events =
      StreamController<Mmrp1LinkEvent>.broadcast();
  final Map<String, int> _pendingProbes = <String, int>{};
  int _nonceCounter = 0;
  String? _peerMmId;

  Stream<Mmrp1LinkEvent> get events => _events.stream;
  bool get peerReady => _peerMmId != null;
  String? get peerMmId => _peerMmId;

  Future<void> discover() {
    return transport.sendRawPayload(
      _codec.encode(
        Mmrp1Hello(
          from: ownMmId,
          to: '*',
          label: ownLabel,
          capabilities: const <String>[
            'DIRECT/1',
            'CHANNEL/1',
            'FILE/1',
            'MMRP/1',
          ],
          reply: false,
        ),
      ),
    );
  }

  Future<void> probe() async {
    final peer = _peerMmId;
    if (peer == null) throw StateError('peer-not-ready');
    final nonce =
        'best-${DateTime.now().microsecondsSinceEpoch}-${++_nonceCounter}';
    _pendingProbes[nonce] = DateTime.now().millisecondsSinceEpoch;
    await transport.sendRawPayload(
      _codec.encode(
        Mmrp1Ping(
          from: ownMmId,
          to: peer,
          nonce: nonce,
          pong: false,
        ),
      ),
    );
  }

  bool _handleInbound(Uint8List payload) {
    final frame = _codec.decode(payload);
    if (frame == null) return false;
    if (frame.from == ownMmId) return true;
    if (frame.to != '*' && frame.to != ownMmId) return true;

    switch (frame) {
      case Mmrp1Hello():
        _peerMmId = frame.from;
        _events.add(Mmrp1PeerReady(mmId: frame.from, label: frame.label));
        if (!frame.reply) {
          unawaited(
            transport.sendRawPayload(
              _codec.encode(
                Mmrp1Hello(
                  from: ownMmId,
                  to: frame.from,
                  label: ownLabel,
                  capabilities: const <String>[
                    'DIRECT/1',
                    'CHANNEL/1',
                    'FILE/1',
                    'MMRP/1',
                  ],
                  reply: true,
                ),
              ),
            ),
          );
        }
      case Mmrp1Ping():
        if (!frame.pong) {
          unawaited(
            transport.sendRawPayload(
              _codec.encode(
                Mmrp1Ping(
                  from: ownMmId,
                  to: frame.from,
                  nonce: frame.nonce,
                  pong: true,
                ),
              ),
            ),
          );
        } else {
          final started = _pendingProbes.remove(frame.nonce);
          if (started != null) {
            _events.add(
              Mmrp1ProbeResult(
                mmId: frame.from,
                rttMs: DateTime.now().millisecondsSinceEpoch - started,
              ),
            );
          }
        }
    }
    return true;
  }

  Future<void> close() async {
    transport.setControlHandler(null);
    await _events.close();
  }
}
