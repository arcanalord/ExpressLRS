import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/app/best_hil_runtime.dart';
import 'package:mesh_messenger_best_v1/src/domain/message.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';

void main() {
  test('two Best-v1 nodes exchange text, dedupe retry, and recipient ACK',
      () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final nodeA = BestHilRuntime(
      localMmId: 'mm:a',
      peerMmId: 'mm:b',
      localBinding: 'lr24:A',
      peerBinding: 'lr24:B',
      link: linkA,
    );
    final nodeB = BestHilRuntime(
      localMmId: 'mm:b',
      peerMmId: 'mm:a',
      localBinding: 'lr24:B',
      peerBinding: 'lr24:A',
      link: linkB,
    );

    var incomingCount = 0;
    final incoming = Completer<BestHilIncomingText>();
    final delivered = Completer<void>();

    final subB = nodeB.events.listen((event) {
      if (event is BestHilIncomingText) {
        incomingCount++;
        if (!incoming.isCompleted) incoming.complete(event);
      }
    });
    final subA = nodeA.events.listen((event) {
      if (event is BestHilDeliveryUpdate &&
          event.messageId == 'm-hil-1' &&
          event.state == DeliveryState.delivered &&
          !delivered.isCompleted) {
        delivered.complete();
      }
    });

    await nodeA.sendText('hello LR24', messageId: 'm-hil-1');

    final inbound =
        await incoming.future.timeout(const Duration(seconds: 1));
    expect(inbound.senderMmId, 'mm:a');
    expect(inbound.text, 'hello LR24');

    await delivered.future.timeout(const Duration(seconds: 1));
    expect(
      nodeA.deliveries['m-hil-1']?.state,
      DeliveryState.delivered,
    );

    await nodeA.sendText('hello LR24', messageId: 'm-hil-1');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(incomingCount, 1);
    expect(
      nodeA.deliveries['m-hil-1']?.state,
      DeliveryState.delivered,
    );

    await subA.cancel();
    await subB.cancel();
    await nodeA.close();
    await nodeB.close();
    await linkA.close();
    await linkB.close();
  });

  test('sequential HIL test runner gets recipient ACK for every message',
      () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final nodeA = BestHilRuntime(
      localMmId: 'mm:a',
      peerMmId: 'mm:b',
      localBinding: 'lr24:A',
      peerBinding: 'lr24:B',
      link: linkA,
    );
    final nodeB = BestHilRuntime(
      localMmId: 'mm:b',
      peerMmId: 'mm:a',
      localBinding: 'lr24:B',
      peerBinding: 'lr24:A',
      link: linkB,
    );

    var incoming = 0;
    final progress = <BestHilTestProgress>[];
    final subB = nodeB.events.listen((event) {
      if (event is BestHilIncomingText) incoming++;
    });
    final subA = nodeA.events.listen((event) {
      if (event is BestHilTestProgress) progress.add(event);
    });

    final result = await nodeA.runTextTest(
      count: 10,
      ackTimeout: const Duration(seconds: 1),
    );

    expect(result.passed, isTrue);
    expect(result.delivered, 10);
    expect(result.failed, 0);
    expect(incoming, 10);
    expect(progress, hasLength(10));
    expect(progress.last.completed, 10);
    expect(progress.last.delivered, 10);

    await subA.cancel();
    await subB.cancel();
    await nodeA.close();
    await nodeB.close();
    await linkA.close();
    await linkB.close();
  });
}
