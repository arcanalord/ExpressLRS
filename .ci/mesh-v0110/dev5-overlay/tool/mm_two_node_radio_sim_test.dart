import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../lib/core/delivery.dart';
import '../lib/core/models.dart';
import '../lib/platform/mm_uart_codec.dart';
import '../lib/platform/mm_uart_external_radio_session.dart';
import '../lib/platform/mm_uart_hil_bench.dart';
import '../lib/platform/mm_uart_message_transport.dart';

final class Net {
  final nodes = <int, Fw>{};
  bool duplicateNext = false;
  void add(Fw fw) => nodes[fw.id] = fw;
  void send(int from, int to, Map<String, dynamic> packet) {
    final target = nodes[to];
    if (target == null) return;
    target.packet({...packet, 'sourceBinding': from});
    final payload = packet['payload'];
    final ack = payload is Map && payload['type'] == 'transport_ack';
    if (duplicateNext && !ack) {
      duplicateNext = false;
      target.packet({...packet, 'sourceBinding': from});
    }
  }
}

final class Fw {
  Fw(this.id, this.net) {
    decoder = MmUartFrameStreamDecoder(onFrame: _frame, onError: (e) => throw e);
    net.add(this);
  }
  final int id;
  final Net net;
  late final MmUartFrameStreamDecoder decoder;
  void Function(Uint8List) emit = (_) {};
  int tx = 0;
  int rx = 0;
  String boot = 'boot-0';
  void input(Uint8List b) => decoder.push(b);
  void resp(int seq, Object? data) => emit(mmUartEncodeFrame(
    type: MmUartFrameType.response, sequence: seq, payload: {'ok': true, 'data': data}));
  void _frame(MmUartFrame f) {
    final raw = f.decodeJsonPayload();
    final p = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    switch (f.type) {
      case MmUartFrameType.hello:
        resp(f.sequence, {'protocol': 1, 'bootId': boot});
      case MmUartFrameType.getInfo:
        resp(f.sequence, {'protocolVersion': 1, 'firmwareVersion': 'sim', 'boardId': 'sim-$id', 'radioFamily': 'SX1280'});
      case MmUartFrameType.getCaps:
        resp(f.sequence, {'networkProtocols': ['MMRP/1'], 'profileIds': ['MM-PHY-24-COMMON-v0'], 'radioFamily': 'SX1280'});
      case MmUartFrameType.getState:
        resp(f.sequence, {'ready': true, 'state': 'ready'});
      case MmUartFrameType.getStats:
        resp(f.sequence, {'tx': tx, 'rx': rx, 'loss': 0, 'retries': 0});
      case MmUartFrameType.compatSelftest:
        resp(f.sequence, {'result': 'PASS'});
      case MmUartFrameType.send:
        final to = int.tryParse('${p['recipientBinding']}');
        final mid = '${p['messageId'] ?? ''}';
        if (to == null || mid.isEmpty) { resp(f.sequence, {'accepted': false}); return; }
        tx++;
        emit(mmUartEncodeFrame(type: MmUartFrameType.txAccepted, payload: {'messageId': mid}));
        resp(f.sequence, {'accepted': true, 'messageId': mid});
        scheduleMicrotask(() => net.send(id, to, {
          'messageId': mid, 'recipientBinding': to, 'payloadType': '${p['payloadType'] ?? ''}', 'payload': p['payload'],
        }));
    }
  }
  void packet(Map<String, dynamic> p) {
    rx++;
    emit(mmUartEncodeFrame(type: MmUartFrameType.rxPacket, payload: p));
  }
  void reset() {
    boot = 'boot-1';
    emit(mmUartEncodeFrame(type: MmUartFrameType.deviceReset, payload: {'bootId': boot}));
  }
}

final class Link implements MmUartHostLink {
  Link(this.fw) { fw.emit = (b) => scheduleMicrotask(() => receiver(b)); }
  final Fw fw;
  bool openState = false;
  void Function(Uint8List) receiver = (_) {};
  void Function(String) disconnected = (_) {};
  @override Future<void> open() async => openState = true;
  @override Future<void> close() async => openState = false;
  @override Future<void> write(Uint8List b) async {
    if (!openState) throw StateError('LINK_CLOSED');
    scheduleMicrotask(() => fw.input(b));
  }
  @override void setReceiver(void Function(Uint8List) r) => receiver = r;
  @override void setDisconnectHandler(void Function(String) h) => disconnected = h;
  @override Map<String, Object?> describe() => {'type': 'sim', 'node': fw.id};
}

DeliveryEnvelope env(String id, String peer, String cls, String payload) => DeliveryEnvelope(
  messageId: id, recipientMmId: peer, messageClass: cls, payload: payload,
  createdAt: DateTime.now().toUtc(), expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  priority: 0, state: DeliveryState.queued);

Future<void> main() async {
  final net = Net();
  final fw1 = Fw(1, net);
  final fw2 = Fw(2, net);
  final s1 = MmUartExternalRadioSession(requestTimeout: const Duration(milliseconds: 500));
  final s2 = MmUartExternalRadioSession(requestTimeout: const Duration(milliseconds: 500));
  var l1 = Link(fw1);
  final l2 = Link(fw2);
  final t1 = MmUartMessageTransport(session: s1, resolveRecipientBinding: (id) => id == 'mm:b' ? 2 : null);
  final t2 = MmUartMessageTransport(session: s2, resolveRecipientBinding: (id) => id == 'mm:a' ? 1 : null);
  final hil1 = MmUartHilBench(s1);
  final hil2 = MmUartHilBench(s2);
  final seen1 = <String>{};
  final seen2 = <String>{};
  final ack1 = <String>{};
  final ack2 = <String>{};
  var dup2 = 0;
  StreamSubscription<MmUartMessageTransportEvent>? sub1;
  StreamSubscription<MmUartMessageTransportEvent>? sub2;
  try {
    await s1.connect(l1);
    await s2.connect(l2);
    if (!t1.isAvailable || !t2.isAvailable) throw StateError('MMRP route unavailable');

    final hilReport = await hil1.run(
      recipientBinding: 2,
      count: 100,
      timeout: const Duration(milliseconds: 300),
    );
    if (!hilReport.passed ||
        hilReport.replied != 100 ||
        !hilReport.ackPass ||
        !hilReport.duplicatePass ||
        !hilReport.mapPointPass) {
      throw StateError('HIL bench failed: ${hilReport.summary()}');
    }
    print('MM_UART_HIL_100_PASS ${hilReport.summary()}');

  sub1 = t1.events.listen((e) async {
    if (e is MmUartRecipientAck) ack1.add(e.messageId);
    if (e is MmUartIncomingMessage) {
      if (!seen1.add(e.messageId)) {}
      await t1.acknowledgeIncoming(messageId: e.messageId, recipientBinding: e.sourceBinding);
    }
  });
  sub2 = t2.events.listen((e) async {
    if (e is MmUartRecipientAck) ack2.add(e.messageId);
    if (e is MmUartIncomingMessage) {
      if (!seen2.add(e.messageId)) dup2++;
      await t2.acknowledgeIncoming(messageId: e.messageId, recipientBinding: e.sourceBinding);
    }
  });

    final text = env('m-text', 'mm:b', 'text', 'hello');
    final r1 = await t1.send(text);
    if (r1.status != TransportSendStatus.accepted) throw StateError('text send rejected');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!seen2.contains('m-text') || !ack1.contains('m-text')) throw StateError('text/ACK failed');

    final point = env('m-map', 'mm:a', 'map_point', jsonEncode({'id': 'p1', 'lat': 47.2, 'lon': 39.7, 'createdAt': DateTime.now().toUtc().toIso8601String()}));
    final r2 = await t2.send(point);
    if (r2.status != TransportSendStatus.accepted) throw StateError('map send rejected');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!seen1.contains('m-map') || !ack2.contains('m-map')) throw StateError('map/ACK failed');

    net.duplicateNext = true;
    await t1.send(env('m-dup', 'mm:b', 'text', 'dedupe'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (dup2 != 1 || seen2.where((id) => id == 'm-dup').length != 1) throw StateError('duplicate suppression harness failed');

    await s1.disconnect();
    final offline = await t1.send(env('m-reconnect', 'mm:b', 'text', 'retry'));
    if (offline.status != TransportSendStatus.unavailable) throw StateError('offline route must be unavailable');
    l1 = Link(fw1);
    await s1.connect(l1);
    final retried = await t1.send(env('m-reconnect', 'mm:b', 'text', 'retry'));
    if (retried.status != TransportSendStatus.accepted) throw StateError('reconnect resend failed');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!ack1.contains('m-reconnect')) throw StateError('reconnect ACK failed');

    final before = s2.bootId;
    fw2.reset();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (s2.state != 'ready' || s2.bootId == before || !s2.supportsMmrp) throw StateError('DEVICE_RESET recovery failed');

    print('MM_TWO_NODE_RADIO_SIM_PASS');
    print('TEXT_ACK=${ack1.contains('m-text')} MAP_ACK=${ack2.contains('m-map')} DUP=$dup2 RESET=${s2.bootId}');
  } finally {
    await sub1?.cancel();
    await sub2?.cancel();
    await hil1.close();
    await hil2.close();
    await t1.close();
    await t2.close();
    await s1.close();
    await s2.close();
  }
}
