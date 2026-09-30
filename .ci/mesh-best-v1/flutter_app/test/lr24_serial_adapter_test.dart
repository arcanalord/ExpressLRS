import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';
import 'package:mesh_messenger_best_v1/src/m03/lr24_serial_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m03/transport_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m12/router.dart';

void main() {
  test('typed LR24 M03 adapter carries opaque prepared bytes end to end',
      () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final adapterA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
    );
    final adapterB = Lr24SerialAdapter(
      link: linkB,
      localBinding: 'lr24:B',
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
    expect(inbound.transportToken, 'transport-token-1');
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

  test('LR24 adapter ignores frames for another transport binding', () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final adapterA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
    );
    final adapterB = Lr24SerialAdapter(
      link: linkB,
      localBinding: 'lr24:B',
    );

    var received = false;
    final sub = adapterB.inbound.listen((_) => received = true);

    final result = await adapterA.submit(
      PreparedTransportPacket(
        routeAttemptId: 'attempt-wrong-binding',
        transportId: 'lr24',
        transportBinding: 'lr24:C',
        protectedBytes: Uint8List.fromList(<int>[7, 8, 9]),
        idempotencyToken: 'token-wrong-binding',
      ),
    );
    expect(result.status, TransportSubmitStatus.accepted);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received, isFalse);

    await sub.cancel();
    await adapterA.close();
    await adapterB.close();
    await linkA.close();
    await linkB.close();
  });
}
