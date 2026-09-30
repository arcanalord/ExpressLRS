import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/app/best_hil_runtime.dart';
import 'package:mesh_messenger_best_v1/src/domain/message.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';

void main() {
  test('runtime refuses user traffic before configured peer discovery', () async {
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

    await expectLater(
      nodeA.sendText('must not leave before discovery'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      nodeA.runTextTest(count: 1),
      throwsA(isA<StateError>()),
    );
    expect(nodeA.deliveries, isEmpty);

    await nodeA.close();
    await linkA.close();
    await linkB.close();
  });

  test('two discovered Best-v1 nodes exchange text, dedupe retry, and ACK',
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

    final peer = await nodeA.discoverPeer(
      timeout: const Duration(seconds: 1),
    );
    expect(peer.mmId, 'mm:b');
    expect(nodeA.peerReady, isTrue);
    expect(nodeB.peerReady, isTrue);
    final probe = await nodeA.probePeer(timeout: const Duration(seconds: 1));
    expect(probe.mmId, 'mm:b');

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

  test('sequential HIL runner gets recipient ACK for every discovered message',
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
    await nodeA.discoverPeer(timeout: const Duration(seconds: 1));

    var incoming = 0;
    final progress = <BestHilTestProgress>[];
    final subB = nodeB.events.listen((event) {
      if (event is BestHilIncomingText) incoming++;
    });
    final subA = nodeA.events.listen((event) {
      if (event is BestHilTestProgress) progress.add(event);
    });

    final result = await nodeA.runTextTest(
      count: 100,
      ackTimeout: const Duration(seconds: 1),
    );

    expect(result.passed, isTrue);
    expect(result.delivered, 100);
    expect(result.failed, 0);
    expect(incoming, 100);
    expect(progress, hasLength(100));
    expect(progress.last.completed, 100);
    expect(progress.last.delivered, 100);

    await subA.cancel();
    await subB.cancel();
    await nodeA.close();
    await nodeB.close();
    await linkA.close();
    await linkB.close();
  });
}
