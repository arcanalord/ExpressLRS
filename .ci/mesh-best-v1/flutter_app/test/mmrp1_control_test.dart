import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';
import 'package:mesh_messenger_best_v1/src/m03/lr24_serial_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m03/mmrp1_control.dart';

void main() {
  test('MMRP1 discovery makes both configured peers ready and probe returns pong',
      () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final transportA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
    );
    final transportB = Lr24SerialAdapter(
      link: linkB,
      localBinding: 'lr24:B',
    );

    final sessionA = Mmrp1ControlSession(
      transport: transportA,
      ownMmId: 'mm:a',
      ownLabel: 'A',
      expectedPeerMmId: 'mm:b',
    );
    final sessionB = Mmrp1ControlSession(
      transport: transportB,
      ownMmId: 'mm:b',
      ownLabel: 'B',
      expectedPeerMmId: 'mm:a',
    );

    final peerB = Completer<Mmrp1PeerReady>();
    final subB = sessionB.events.listen((event) {
      if (event is Mmrp1PeerReady && !peerB.isCompleted) {
        peerB.complete(event);
      }
    });

    final peerA =
        await sessionA.discover(timeout: const Duration(seconds: 1));
    expect(peerA.mmId, 'mm:b');
    expect((await peerB.future.timeout(const Duration(seconds: 1))).mmId, 'mm:a');
    expect(sessionA.peerReady, isTrue);
    expect(sessionB.peerReady, isTrue);

    final pong =
        await sessionA.probe(timeout: const Duration(seconds: 1));
    expect(pong.mmId, 'mm:b');
    expect(pong.nonce, isNotEmpty);
    expect(pong.rttMs, greaterThanOrEqualTo(0));

    await subB.cancel();
    await sessionA.close();
    await sessionB.close();
    await transportA.close();
    await transportB.close();
    await linkA.close();
    await linkB.close();
  });

  test('MMRP1 ignores a valid hello from the wrong configured peer', () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final transportA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
    );
    final transportB = Lr24SerialAdapter(
      link: linkB,
      localBinding: 'lr24:B',
    );
    final sessionA = Mmrp1ControlSession(
      transport: transportA,
      ownMmId: 'mm:a',
      ownLabel: 'A',
      expectedPeerMmId: 'mm:b',
    );
    final codec = Mmrp1ControlCodec();

    await transportB.sendRawPayload(
      codec.encode(
        const Mmrp1Hello(
          from: 'mm:c',
          to: '*',
          label: 'C',
          capabilities: <String>['MMRP/1'],
          reply: false,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(sessionA.peerReady, isFalse);
    expect(sessionA.peerMmId, isNull);

    await sessionA.close();
    await transportA.close();
    await transportB.close();
    await linkA.close();
    await linkB.close();
  });

  test('MMRP1 discover and probe timeout are explicit failures', () async {
    final linkA = MemoryLr24ByteStreamLink();
    final linkB = MemoryLr24ByteStreamLink();
    linkA.connectPeer(linkB);
    linkB.connectPeer(linkA);

    final transportA = Lr24SerialAdapter(
      link: linkA,
      localBinding: 'lr24:A',
    );
    final transportB = Lr24SerialAdapter(
      link: linkB,
      localBinding: 'lr24:B',
    );

    final sessionA = Mmrp1ControlSession(
      transport: transportA,
      ownMmId: 'mm:a',
      ownLabel: 'A',
      expectedPeerMmId: 'mm:b',
    );

    // No control session on B: hello is transported but nobody replies.
    await expectLater(
      sessionA.discover(timeout: const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );
    expect(sessionA.peerReady, isFalse);

    final sessionB = Mmrp1ControlSession(
      transport: transportB,
      ownMmId: 'mm:b',
      ownLabel: 'B',
      expectedPeerMmId: 'mm:a',
    );
    await sessionA.discover(timeout: const Duration(seconds: 1));
    expect(sessionA.peerReady, isTrue);

    // Remove B control handler but leave the byte transport open.
    await sessionB.close();
    await expectLater(
      sessionA.probe(timeout: const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );

    await sessionA.close();
    await transportA.close();
    await transportB.close();
    await linkA.close();
    await linkB.close();
  });

  test('MMRP1 codec rejects malformed and wrong-version payloads', () {
    final codec = Mmrp1ControlCodec();
    expect(codec.decode(Uint8List.fromList(<int>[0xff, 0xfe])), isNull);
    expect(
      codec.decode(
        Uint8List.fromList(
          '{"v":2,"p":"MMRP/1","k":"hello","from":"mm:b","to":"mm:a"}'
              .codeUnits,
        ),
      ),
      isNull,
    );
    expect(
      codec.decode(
        Uint8List.fromList(
          '{"v":1,"p":"MMRP/2","k":"hello","from":"mm:b","to":"mm:a"}'
              .codeUnits,
        ),
      ),
      isNull,
    );
  });
}
