import 'dart:async';
import 'dart:typed_data';

import '../lib/platform/mm_uart_codec.dart';
import '../lib/platform/mm_uart_external_radio_session.dart';

final class FakeFirmware {
  late final MmUartFrameStreamDecoder decoder;
  void Function(Uint8List bytes) emit = (_) {};
  String bootId = 'boot-test';
  int tx = 0;

  FakeFirmware() {
    decoder = MmUartFrameStreamDecoder(
      onFrame: _handle,
      onError: (error) => throw error,
    );
  }

  void receive(Uint8List bytes) => decoder.push(bytes);

  void _response(int sequence, Object? data, {bool ok = true, String? error}) {
    emit(
      mmUartEncodeFrame(
        type: MmUartFrameType.response,
        sequence: sequence,
        payload: {'ok': ok, 'data': data, 'error': error},
      ),
    );
  }

  void _handle(MmUartFrame frame) {
    final raw = frame.decodeJsonPayload();
    final payload = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    switch (frame.type) {
      case MmUartFrameType.hello:
        _response(frame.sequence, {'protocol': 1, 'bootId': bootId});
      case MmUartFrameType.getInfo:
        _response(frame.sequence, {
          'protocolVersion': 1,
          'firmwareFamily': 'mesh-radio-test',
          'firmwareVersion': '0.4.1-test',
          'boardId': 'ep2',
          'radioFamily': 'SX1280',
          'buildHash': 'test',
        });
      case MmUartFrameType.getCaps:
        _response(frame.sequence, {
          'radioFamily': 'SX1280',
          'profileIds': ['MM-PHY-24-COMMON-v0'],
          'networkProtocols': ['MMRP/1'],
          'maxPayload': 512,
          'rssiAvailable': true,
          'snrAvailable': true,
          'waypointAvailable': true,
        });
      case MmUartFrameType.getState:
        _response(frame.sequence, {'ready': true, 'state': 'ready'});
      case MmUartFrameType.getStats:
        _response(frame.sequence, {'tx': tx, 'rx': 0, 'rssi': -60, 'snr': 8});
      case MmUartFrameType.compatSelftest:
        _response(frame.sequence, {
          'hostProtocol': 'MM-UART/1',
          'networkProtocol': 'MMRP/1',
          'codecRoundTrip': true,
          'crcReject': true,
          'result': 'PASS',
        });
      case MmUartFrameType.send:
        tx++;
        emit(
          mmUartEncodeFrame(
            type: MmUartFrameType.txAccepted,
            payload: {'messageId': payload['messageId']},
          ),
        );
        _response(frame.sequence, {
          'accepted': true,
          'messageId': payload['messageId'],
        });
    }
  }

  void emitIncoming(Map<String, Object?> packet) {
    emit(mmUartEncodeFrame(type: MmUartFrameType.rxPacket, payload: packet));
  }
}

final class FakeLink implements MmUartHostLink {
  FakeLink(this.firmware) {
    firmware.emit = (bytes) => scheduleMicrotask(() => receiver(bytes));
  }
  final FakeFirmware firmware;
  bool opened = false;
  void Function(Uint8List bytes) receiver = (_) {};
  void Function(String reason) disconnectHandler = (_) {};

  @override
  Future<void> open() async => opened = true;
  @override
  Future<void> close() async => opened = false;
  @override
  Future<void> write(Uint8List bytes) async {
    if (!opened) throw StateError('LINK_CLOSED');
    scheduleMicrotask(() => firmware.receive(bytes));
  }

  @override
  void setReceiver(void Function(Uint8List bytes) value) => receiver = value;
  @override
  void setDisconnectHandler(void Function(String reason) value) =>
      disconnectHandler = value;
  @override
  Map<String, Object?> describe() => const {'type': 'fake'};
}

Future<void> main() async {
  final firmware = FakeFirmware();
  final session = MmUartExternalRadioSession();
  final packets = <Map<String, dynamic>>[];
  final accepted = <String>[];
  final sub = session.events.listen((event) {
    if (event is ExternalRadioPacketEvent) packets.add(event.packet);
    if (event is ExternalRadioTxAcceptedEvent) {
      accepted.add('${event.tx['messageId']}');
    }
  });

  final snapshot = await session.connect(FakeLink(firmware));
  if (snapshot.state != 'ready' || !session.supportsMmrp) {
    throw StateError('handshake/capabilities failed');
  }
  final compat = await session.compatSelftest();
  if (compat['result'] != 'PASS') throw StateError('compat selftest failed');

  final send = await session.send(
    messageId: 'm-1',
    recipientBinding: 2,
    payload: {'text': 'hello'},
    payloadType: 'text',
  );
  if (send is! Map || send['accepted'] != true) throw StateError('SEND failed');
  await Future<void>.delayed(Duration.zero);
  if (!accepted.contains('m-1')) throw StateError('TX_ACCEPTED event missing');

  firmware.emitIncoming({
    'messageId': 'm-rx',
    'sourceBinding': 2,
    'recipientBinding': 1,
    'payloadType': 'map_point',
    'payload': {'id': 'p-1', 'lat': 47.2357, 'lon': 39.7015},
  });
  await Future<void>.delayed(Duration.zero);
  if (packets.length != 1 || packets.single['messageId'] != 'm-rx') {
    throw StateError('RX_PACKET failed');
  }

  final stats = await session.refreshStats();
  if (stats['tx'] != 1) throw StateError('stats failed');
  await session.disconnect();
  await sub.cancel();
  await session.close();
  print('MM_UART_EXTERNAL_RADIO_SESSION_PASS');
}
