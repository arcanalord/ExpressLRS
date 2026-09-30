import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/protocol/mmrp1_channel.dart';

void main() {
  const codec = Mmrp1ChannelCodec();

  test('CHANNEL/1 data bytes match MM U1 canonical JSON shape', () {
    final encoded = codec.encode(
      const Mmrp1ChannelData(
        from: 'mm:a',
        channel: 'general',
        messageId: 'm-001',
        payload: 'hello',
      ),
    );

    expect(
      utf8.decode(encoded),
      '{"v":1,"p":"MMRP/1","k":"channel_data","id":"m-001",'
      '"from":"mm:a","channel":"general","class":"text","payload":"hello"}',
    );

    final decoded = codec.decode(encoded);
    expect(decoded, isA<Mmrp1ChannelData>());
    final data = decoded! as Mmrp1ChannelData;
    expect(data.from, 'mm:a');
    expect(data.channel, 'general');
    expect(data.messageId, 'm-001');
    expect(data.payload, 'hello');
  });

  test('CHANNEL/1 receipt bytes match MM U1 canonical JSON shape', () {
    final encoded = codec.encode(
      const Mmrp1ChannelReceipt(
        from: 'mm:b',
        channel: 'general',
        messageId: 'm-001',
      ),
    );

    expect(
      utf8.decode(encoded),
      '{"v":1,"p":"MMRP/1","k":"channel_receipt","id":"m-001",'
      '"from":"mm:b","channel":"general"}',
    );

    final decoded = codec.decode(encoded);
    expect(decoded, isA<Mmrp1ChannelReceipt>());
    final receipt = decoded! as Mmrp1ChannelReceipt;
    expect(receipt.from, 'mm:b');
    expect(receipt.messageId, 'm-001');
  });

  test('MM U1-originated CHANNEL/1 bytes decode in Best-v1', () {
    final mmU1Bytes = Uint8List.fromList(
      utf8.encode(
        '{"v":1,"p":"MMRP/1","k":"channel_data","id":"from-u1",'
        '"from":"mm:u1","channel":"general","class":"text",'
        '"payload":"u1 -> best"}',
      ),
    );

    final decoded = codec.decode(mmU1Bytes);
    expect(decoded, isA<Mmrp1ChannelData>());
    final data = decoded! as Mmrp1ChannelData;
    expect(data.from, 'mm:u1');
    expect(data.messageId, 'from-u1');
    expect(data.payload, 'u1 -> best');
  });

  test('CHANNEL/1 rejects wrong version, class and oversized text', () {
    expect(
      codec.decode(
        Uint8List.fromList(
          utf8.encode(
            '{"v":2,"p":"MMRP/1","k":"channel_receipt","id":"m1",'
            '"from":"mm:b","channel":"general"}',
          ),
        ),
      ),
      isNull,
    );
    expect(
      codec.decode(
        Uint8List.fromList(
          utf8.encode(
            '{"v":1,"p":"MMRP/1","k":"channel_data","id":"m1",'
            '"from":"mm:b","channel":"general","class":"file",'
            '"payload":"x"}',
          ),
        ),
      ),
      isNull,
    );
    expect(
      () => codec.encode(
        Mmrp1ChannelData(
          from: 'mm:a',
          channel: 'general',
          messageId: 'too-big',
          payload: 'x' * (Mmrp1ChannelCodec.maxTextBytes + 1),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
