import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/app_storage.dart';
import '../lib/core/messenger_core.dart';
import '../lib/core/models.dart';
import '../lib/platform/mm_uart_codec.dart';
import '../lib/platform/mm_uart_external_radio_session.dart';
import '../lib/platform/mm_uart_message_transport.dart';

final class SimRadio {
  SimRadio(this.nodeId) {
    decoder = MmUartFrameStreamDecoder(
      onFrame: _handleFrame,
      onError: (error) => throw error,
    );
  }

  final int nodeId;
  late final MmUartFrameStreamDecoder decoder;
  SimRadio? peer;
  void Function(Uint8List bytes) emitHost = (_) {};
  String bootId = 'boot-a';
  bool duplicateNextRx = false;
  int tx = 0;
  int rx = 0;
  int retries = 0;

  void receiveHost(Uint8List bytes) => decoder.push(bytes);

  void _emitFrame({required int type, int sequence = 0, Object? payload}) {
    final bytes = mmUartEncodeFrame(
      type: type,
      sequence: sequence,
      payload: payload,
    );
    scheduleMicrotask(() => emitHost(bytes));
  }

  void _response(int sequence, Object? data, {bool ok = true, String? error}) {
    _emitFrame(
      type: MmUartFrameType.response,
      sequence: sequence,
      payload: {'ok': ok, 'data': data, 'error': error},
    );
  }

  void _handleFrame(MmUartFrame frame) {
    final raw = frame.decodeJsonPayload();
    final payload = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};

    switch (frame.type) {
      case MmUartFrameType.hello:
        _response(frame.sequence, {'protocol': 1, 'bootId': bootId});
      case MmUartFrameType.getInfo:
        _response(frame.sequence, {
          'protocolVersion': 1,
          'firmwareFamily': 'mesh-radio-sim',
          'firmwareVersion': '0.4.1-sim',
          'boardId': nodeId == 1 ? 'sim-a' : 'sim-b',
          'radioFamily': 'SX1280',
          'buildHash': 'sim',
          'bootId': bootId,
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
        _response(frame.sequence, {
          'tx': tx,
          'rx': rx,
          'loss': 0,
          'retries': retries,
          'rssi10': -610,
          'snr10': 75,
          'rttMs': 24,
        });
      case MmUartFrameType.compatSelftest:
        _response(frame.sequence, {
          'ok': true,
          'result': 'PASS',
          'hostProtocol': 'MM-UART/1',
          'networkProtocol': 'MMRP/1',
        });
      case MmUartFrameType.send:
        tx++;
        _emitFrame(
          type: MmUartFrameType.txAccepted,
          payload: {'messageId': payload['messageId']},
        );
        _response(frame.sequence, {
          'accepted': true,
          'messageId': payload['messageId'],
        });

        final target = peer;
        if (target != null) {
          final packet = <String, Object?>{
            'messageId': payload['messageId'],
            'sourceBinding': nodeId,
            'recipientBinding': payload['recipientBinding'],
            'payloadType': payload['payloadType'],
            'payload': payload['payload'],
          };
          scheduleMicrotask(() {
            target._receiveAir(packet);
            if (duplicateNextRx) {
              target._receiveAir(packet);
              duplicateNextRx = false;
            }
          });
        }
      case MmUartFrameType.enterOta:
        _response(frame.sequence, {
          'ssid': nodeId == 1 ? 'MM-OTA-A' : 'MM-OTA-B',
          'password': '12345678',
          'url': 'http://10.0.0.1',
        });
      case MmUartFrameType.exitOta:
        _response(frame.sequence, {'ok': true});
      case MmUartFrameType.reboot:
        _response(frame.sequence, {'accepted': true});
    }
  }

  void _receiveAir(Map<String, Object?> packet) {
    rx++;
    _emitFrame(type: MmUartFrameType.rxPacket, payload: packet);
  }

  void reset(String newBootId) {
    bootId = newBootId;
    _emitFrame(
      type: MmUartFrameType.deviceReset,
      payload: {'bootId': bootId},
    );
  }
}

final class SimLink implements MmUartHostLink {
  SimLink(this.radio) {
    radio.emitHost = (bytes) {
      if (opened) receiver(bytes);
    };
  }

  final SimRadio radio;
  bool opened = false;
  void Function(Uint8List bytes) receiver = (_) {};
  void Function(String reason) disconnectHandler = (_) {};

  @override
  Future<void> open() async {
    opened = true;
  }

  @override
  Future<void> close() async {
    opened = false;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (!opened) throw StateError('LINK_CLOSED');
    scheduleMicrotask(() => radio.receiveHost(bytes));
  }

  @override
  void setReceiver(void Function(Uint8List bytes) value) => receiver = value;

  @override
  void setDisconnectHandler(void Function(String reason) value) =>
      disconnectHandler = value;

  @override
  Map<String, Object?> describe() => {
        'type': 'two-node-sim',
        'nodeId': radio.nodeId,
      };
}

Future<void> _drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('mesh-mm-uart-2node-');
  try {
    final radioA = SimRadio(1);
    final radioB = SimRadio(2);
    radioA.peer = radioB;
    radioB.peer = radioA;

    final sessionA = MmUartExternalRadioSession();
    final sessionB = MmUartExternalRadioSession();
    final transportA = MmUartMessageTransport(
      session: sessionA,
      resolveRecipientBinding: (mmId) => mmId == 'mm:b' ? 2 : null,
    );
    final transportB = MmUartMessageTransport(
      session: sessionB,
      resolveRecipientBinding: (mmId) => mmId == 'mm:a' ? 1 : null,
    );

    final storageA = AppStorage(Directory(root.path + '/a'));
    final storageB = AppStorage(Directory(root.path + '/b'));
    final coreA = MeshMessengerCore(
      ownMmId: 'mm:a',
      storage: storageA,
      transports: [transportA],
    );
    final coreB = MeshMessengerCore(
      ownMmId: 'mm:b',
      storage: storageB,
      transports: [transportB],
    );

    final subA = transportA.events.listen((event) async {
      if (event is MmUartRecipientAck) {
        await coreA.recipientDeliveryResult(
          messageId: event.messageId,
          fromMmId: 'mm:b',
          ok: true,
        );
      } else if (event is MmUartIncomingMessage) {
        if (event.messageClass == 'text') {
          final payload = event.payload as Map;
          await coreA.receiveText(
            messageId: event.messageId,
            fromMmId: 'mm:b',
            text: payload['text'].toString(),
          );
        } else if (event.messageClass == 'map_point') {
          await coreA.receiveMapPoint(
            messageId: event.messageId,
            fromMmId: 'mm:b',
            payload: jsonEncode(event.payload),
          );
        }
        await transportA.acknowledgeIncoming(
          messageId: event.messageId,
          recipientBinding: event.sourceBinding,
        );
      }
    });

    final subB = transportB.events.listen((event) async {
      if (event is MmUartRecipientAck) {
        await coreB.recipientDeliveryResult(
          messageId: event.messageId,
          fromMmId: 'mm:a',
          ok: true,
        );
      } else if (event is MmUartIncomingMessage) {
        if (event.messageClass == 'text') {
          final payload = event.payload as Map;
          await coreB.receiveText(
            messageId: event.messageId,
            fromMmId: 'mm:a',
            text: payload['text'].toString(),
          );
        } else if (event.messageClass == 'map_point') {
          await coreB.receiveMapPoint(
            messageId: event.messageId,
            fromMmId: 'mm:a',
            payload: jsonEncode(event.payload),
          );
        }
        await transportB.acknowledgeIncoming(
          messageId: event.messageId,
          recipientBinding: event.sourceBinding,
        );
      }
    });

    await sessionA.connect(SimLink(radioA));
    await sessionB.connect(SimLink(radioB));
    if (!transportA.isAvailable || !transportB.isAvailable) {
      throw StateError('both transports must be ready');
    }

    radioA.duplicateNextRx = true;
    final text = await coreA.sendText(peerMmId: 'mm:b', text: 'hello-radio');
    await _drain();
    if (coreA.deliveryById(text.messageId)?.state != DeliveryState.delivered) {
      throw StateError('final recipient ACK did not deliver text');
    }
    final bText = await coreB.messagesFor('mm:a');
    if (bText.where((m) => m.messageId == text.messageId).length != 1) {
      throw StateError('duplicate text was not suppressed');
    }

    final point = MapPoint(
      id: 'p-1',
      latitude: 54.318,
      longitude: 48.397,
      createdAt: DateTime.utc(2026, 9, 26),
      label: 'Test point',
    );
    final map = await coreB.sendMapPoint(peerMmId: 'mm:a', point: point);
    await _drain();
    if (coreB.deliveryById(map.messageId)?.state != DeliveryState.delivered) {
      throw StateError('final recipient ACK did not deliver MapPoint');
    }
    final aMessages = await coreA.messagesFor('mm:b');
    final receivedPoint = aMessages.where((m) => m.messageId == map.messageId);
    if (receivedPoint.length != 1 ||
        receivedPoint.single.mapPoint?.id != point.id) {
      throw StateError('MapPoint round-trip failed');
    }

    await sessionA.disconnect();
    final queued = await coreA.sendText(
      peerMmId: 'mm:b',
      text: 'survive-reconnect',
    );
    if (coreA.deliveryById(queued.messageId)?.state != DeliveryState.noRoute) {
      throw StateError('offline send must remain queued/noRoute');
    }
    final originalId = queued.messageId;

    await sessionA.connect(SimLink(radioA));
    await coreA.maintenance();
    await _drain();
    if (coreA.deliveryById(originalId)?.state != DeliveryState.delivered) {
      throw StateError('queued message did not deliver after reconnect');
    }
    final reconnected = await coreB.messagesFor('mm:a');
    if (reconnected.where((m) => m.messageId == originalId).length != 1) {
      throw StateError('messageId changed or duplicated after reconnect');
    }

    radioA.reset('boot-b');
    await _drain();
    if (sessionA.state != 'ready' || sessionA.bootId != 'boot-b') {
      throw StateError('DEVICE_RESET recovery handshake failed');
    }

    final statsA = await sessionA.refreshStats();
    final statsB = await sessionB.refreshStats();
    if (statsA['tx'] == null || statsB['rx'] == null) {
      throw StateError('stats unavailable');
    }

    await subA.cancel();
    await subB.cancel();
    await transportA.close();
    await transportB.close();
    await coreA.close();
    await coreB.close();
    await sessionA.close();
    await sessionB.close();

    print('MM_UART_TWO_NODE_TEXT_PASS');
    print('MM_UART_TWO_NODE_MAPPOINT_PASS');
    print('MM_UART_TWO_NODE_ACK_PASS');
    print('MM_UART_TWO_NODE_DEDUPE_PASS');
    print('MM_UART_TWO_NODE_RECONNECT_PASS');
    print('MM_UART_TWO_NODE_DEVICE_RESET_PASS');
  } finally {
    await root.delete(recursive: true);
  }
}
