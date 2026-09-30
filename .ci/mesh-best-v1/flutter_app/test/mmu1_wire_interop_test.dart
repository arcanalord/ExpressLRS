import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/app/best_hil_runtime.dart';
import 'package:mesh_messenger_best_v1/src/domain/message.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';
import 'package:mesh_messenger_best_v1/src/m03/mm_serial_codec.dart';

void main() {
  test('Best-v1 interoperates with literal MM U1 MMRP1 wire fixture', () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkU1 = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkU1);
    linkU1.connectPeer(linkA);

    final nodeA = BestHilRuntime(
      localMmId: 'mm:a',
      peerMmId: 'mm:u1',
      localBinding: 'lr24:A',
      peerBinding: 'lr24:U1',
      link: linkA,
    );

    final u1Codec = MmSerialCodec();
    final seenPayloads = <String>[];

    final sub = linkU1.received.listen((chunk) {
      for (final payload in u1Codec.feed(chunk)) {
        final text = utf8.decode(payload);
        seenPayloads.add(text);

        if (text.contains('"k":"hello"') &&
            text.contains('"from":"mm:a"')) {
          final reply = Uint8List.fromList(
            utf8.encode(
              '{"v":1,"p":"MMRP/1","k":"hello_reply",'
              '"from":"mm:u1","to":"mm:a","label":"MM U1",'
              '"caps":["CHANNEL/1","DIRECT/1","FILE/1","MMRP/1"]}',
            ),
          );
          unawaited(linkU1.write(u1Codec.encode(reply)));
          continue;
        }

        if (text ==
            '{"v":1,"p":"MMRP/1","k":"channel_data","id":"m-interop",'
                '"from":"mm:a","channel":"general","class":"text",'
                '"payload":"hello U1"}') {
          final receipt = Uint8List.fromList(
            utf8.encode(
              '{"v":1,"p":"MMRP/1","k":"channel_receipt",'
              '"id":"m-interop","from":"mm:u1","channel":"general"}',
            ),
          );
          unawaited(linkU1.write(u1Codec.encode(receipt)));
        }
      }
    });

    final peer = await nodeA.discoverPeer(
      timeout: const Duration(seconds: 1),
    );
    expect(peer.mmId, 'mm:u1');

    final delivered = Completer<void>();
    final eventSub = nodeA.events.listen((event) {
      if (event is BestHilDeliveryUpdate &&
          event.messageId == 'm-interop' &&
          event.state == DeliveryState.delivered &&
          !delivered.isCompleted) {
        delivered.complete();
      }
    });

    final record = await nodeA.sendText(
      'hello U1',
      messageId: 'm-interop',
    );
    expect(record.state, DeliveryState.sentToTransport);
    await delivered.future.timeout(const Duration(seconds: 1));
    expect(
      nodeA.deliveries['m-interop']?.state,
      DeliveryState.delivered,
    );

    expect(
      seenPayloads.any((payload) => payload.startsWith('ML1')),
      isFalse,
    );
    expect(
      seenPayloads,
      contains(
        '{"v":1,"p":"MMRP/1","k":"channel_data","id":"m-interop",'
        '"from":"mm:a","channel":"general","class":"text",'
        '"payload":"hello U1"}',
      ),
    );

    await eventSub.cancel();
    await sub.cancel();
    await nodeA.close();
    await linkA.close();
    await linkU1.close();
  });
}
