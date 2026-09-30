import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';
import 'package:mesh_messenger_best_v1/src/m03/lr24_serial_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m03/mm_serial_codec.dart';
import 'package:mesh_messenger_best_v1/src/m03/transport_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m12/router.dart';

void main() {
  test('typed LR24 M03 carries opaque prepared bytes transparently', () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final adapterA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
      peerBinding: 'lr24:B',
    );
    final adapterB = Lr24SerialAdapter(
      link: linkB,
      localBinding: 'lr24:B',
      peerBinding: 'lr24:A',
    );

    final received = Completer<TransportInboundFrame>();
    final sub = adapterB.inbound.listen((frame) {
      if (!received.isCompleted) received.complete(frame);
    });

    final original = Uint8List.fromList(<int>[0, 1, 2, 3, 0, 255, 42]);
    final packet = PreparedTransportPacket(
      routeAttemptId: 'attempt-1',
      transportId: 'lr24',
      transportBinding: 'lr24:B',
      protectedBytes: original,
      idempotencyToken: 'transport-token-1',
    );

    final result = await adapterA.submit(packet);
    expect(result.status, TransportSubmitStatus.accepted);

    final inbound = await received.future.timeout(const Duration(seconds: 1));
    expect(inbound.transportId, 'lr24');
    expect(inbound.sourceBinding, 'lr24:A');
    expect(inbound.transportToken, 'mm-serial/1');
    expect(inbound.protectedBytes, original);

    final exposed = inbound.protectedBytes;
    exposed[0] = 99;
    expect(inbound.protectedBytes, original);

    await sub.cancel();
    await adapterA.close();
    await adapterB.close();
    await linkA.close();
    await linkB.close();
  });

  test('wire payload is exactly prepared bytes inside MM-SERIAL, no ML1 wrapper',
      () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final adapterA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
      peerBinding: 'lr24:B',
    );
    final wireCodec = MmSerialCodec();
    final raw = Completer<Uint8List>();
    final sub = linkB.received.listen((bytes) {
      for (final payload in wireCodec.feed(bytes)) {
        if (!raw.isCompleted) raw.complete(payload);
      }
    });

    final payload = Uint8List.fromList(
      '{"v":1,"p":"MMRP/1","k":"channel_receipt","id":"m1",'
              '"from":"mm:b","channel":"general"}'
          .codeUnits,
    );
    final result = await adapterA.submit(
      PreparedTransportPacket(
        routeAttemptId: 'attempt-raw',
        transportId: 'lr24',
        transportBinding: 'lr24:B',
        protectedBytes: payload,
        idempotencyToken: 'm1',
      ),
    );

    expect(result.status, TransportSubmitStatus.accepted);
    expect(await raw.future.timeout(const Duration(seconds: 1)), payload);

    await sub.cancel();
    await adapterA.close();
    await linkA.close();
    await linkB.close();
  });

  test('LR24 adapter rejects wrong transport id before writing', () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final adapterA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
      peerBinding: 'lr24:B',
    );
    var rawWrites = 0;
    final sub = linkB.received.listen((_) => rawWrites++);

    final result = await adapterA.submit(
      PreparedTransportPacket(
        routeAttemptId: 'attempt-wrong-transport',
        transportId: 'internet',
        transportBinding: 'lr24:B',
        protectedBytes: Uint8List.fromList(<int>[7, 8, 9]),
        idempotencyToken: 'token-wrong-transport',
      ),
    );

    expect(result.status, TransportSubmitStatus.rejected);
    expect(result.detail, 'lr24-wrong-transport');
    await Future<void>.delayed(Duration.zero);
    expect(rawWrites, 0);

    await sub.cancel();
    await adapterA.close();
    await linkA.close();
    await linkB.close();
  });
}
