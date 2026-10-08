import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_flutter/core/contact_card.dart';
import 'package:mesh_messenger_flutter/core/models.dart';
import 'package:mesh_messenger_flutter/platform/mm_uart_codec.dart';
import 'package:mesh_messenger_flutter/platform/mm_uart_external_radio_session.dart';
import 'package:mesh_messenger_flutter/platform/radio_capability_contract.dart';

class _CycloneMock implements MmUartHostLink {
  _CycloneMock({this.txOff = false, this.legacy = false});
  final bool txOff;
  final bool legacy;
  bool ready = false;
  bool configured = false;
  int sent = 0;
  late void Function(Uint8List) receiver;

  @override
  Future<void> open() async {
    receiver(mmUartEncodeFrame(
      type: MmUartFrameType.ready,
      payload: {'state': 'idle', 'txDisabled': txOff},
    ));
  }
  @override
  Future<void> close() async {}
  @override
  void setReceiver(void Function(Uint8List) f) => receiver = f;
  @override
  void setDisconnectHandler(void Function(String) handler) {}
  @override
  Map<String, Object?>? describe() => {'type': 'fake', 'baudRate': 115200};

  @override
  Future<void> write(Uint8List bytes) async {
    final frame = mmUartDecodeFrame(bytes.sublist(0, bytes.length - 1));
    Object data;
    if (frame.type == MmUartFrameType.hello) {
      data = {'bootId': 'boot1', 'nodeBinding': 'node-ab12cd34'};
    } else if (frame.type == MmUartFrameType.getInfo) {
      data = {
        'protocolVersion': 1,
        'hostProtocol': 'MM-UART/1',
        'networkProtocol': 'MMRP/1',
        'boardId': 'CYCLONE_900_MICRO_TX',
      };
    } else if (frame.type == MmUartFrameType.getCaps) {
      data = {
        'profileIds': ['MM-PHY-915-LORA-RANGE-v1'],
        if (!legacy) 'networkProtocols': ['MMRP/1'],
      };
    } else if (frame.type == MmUartFrameType.getState) {
      data = {'ready': ready, 'state': ready ? 'ready' : 'idle',
        'txDisabled': txOff, 'otaActive': false, 'fhssMode': 'FIXED'};
    } else if (frame.type == MmUartFrameType.setProfile) {
      configured = true;
      data = {'requiresRadioInit': true};
    } else if (frame.type == MmUartFrameType.radioInit) {
      ready = configured;
      data = {'ready': ready};
    } else if (frame.type == MmUartFrameType.send) {
      ++sent;
      data = {'accepted': true};
    } else {
      data = {};
    }
    receiver(mmUartEncodeFrame(
      type: MmUartFrameType.response,
      sequence: frame.sequence,
      payload: {'ok': true, 'data': data},
    ));
  }
}

void main() {
  test('M03 caps fallback is restricted to explicit MM-UART v1', () {
    final info = RadioInfo.fromJson({
      'protocolVersion': 1, 'hostProtocol': 'MM-UART/1',
      'networkProtocol': 'MMRP/1',
    });
    expect(RadioCapabilities.fromJson({}, info: info).supportsMmrp, isTrue);
    expect(RadioCapabilities.fromJson({
      'networkProtocols': <String>[],
    }, info: info).supportsMmrp, isFalse);
    expect(RadioCapabilities.fromJson({}, info: RadioInfo.fromJson({
      'protocolVersion': 1, 'hostProtocol': 'CRSF',
      'networkProtocol': 'MMRP/1',
    })).supportsMmrp, isFalse);
  });

  test('M03 opaque contact QR/JSON never implies verification', () {
    const card = ContactCard(
      mmId: 'mm:alice001', displayName: 'Alice',
      radioNodeBinding: 'node-ab12cd34',
    );
    expect(ContactCard.parse(card.encode()).radioNodeBinding, 'node-ab12cd34');
    expect(ContactCard.parse(card.encodeJson()).radioNodeBinding,
        'node-ab12cd34');
    final stored = const Contact(
      mmId: 'mm:alice001', displayName: 'Alice',
      radioNodeBinding: 'node-ab12cd34', verified: false,
    );
    final restored = Contact.fromJson(stored.toJson().cast<String, dynamic>());
    expect(restored.radioNodeBinding, 'node-ab12cd34');
    expect(restored.verified, isFalse);
  });

  test('boot READY and service TX-OFF cannot authorize SEND', () async {
    final mock = _CycloneMock(txOff: true);
    final s = MmUartExternalRadioSession();
    await s.connect(mock);
    expect(s.localNodeBinding, 'node-ab12cd34');
    expect(s.canSend, isFalse);
    await s.activateProfile('MM-PHY-915-LORA-RANGE-v1');
    expect(s.state, 'ready');
    expect(s.canSend, isFalse);
    await expectLater(s.send(
      messageId: 'test1', recipientBinding: 'node-deadbeef',
      payloadType: 'text', payload: {'text': 'hello'},
    ), throwsStateError);
    expect(mock.sent, 0);
    await s.close();
  });

  test('legacy Cyclone becomes send-ready only after radio init', () async {
    final mock = _CycloneMock(legacy: true);
    final s = MmUartExternalRadioSession();
    await s.connect(mock);
    expect(s.supportsMmrp, isTrue);
    expect(s.canSend, isFalse);
    await expectLater(s.activateProfile('UNSUPPORTED'), throwsStateError);
    await s.activateProfile('MM-PHY-915-LORA-RANGE-v1');
    expect(s.canSend, isTrue);
    await s.send(messageId: 'test2', recipientBinding: 'node-deadbeef',
      payloadType: 'text', payload: {'text': 'hello'});
    expect(mock.sent, 1);
    await s.close();
  });
}
