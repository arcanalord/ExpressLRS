import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/m03/byte_stream_link.dart';
import 'package:mesh_messenger_best_v1/src/m03/lr24_serial_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m03/mmrp1_control.dart';

void main() {
  test('MMRP1 discovery makes both peers ready and probe returns pong', () async {
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
    );
    final sessionB = Mmrp1ControlSession(
      transport: transportB,
      ownMmId: 'mm:b',
      ownLabel: 'B',
    );

    final peerA = Completer<Mmrp1PeerReady>();
    final peerB = Completer<Mmrp1PeerReady>();
    final pongA = Completer<Mmrp1ProbeResult>();

    final subA = sessionA.events.listen((event) {
      if (event is Mmrp1PeerReady && !peerA.isCompleted) {
        peerA.complete(event);
      }
      if (event is Mmrp1ProbeResult && !pongA.isCompleted) {
        pongA.complete(event);
      }
    });
    final subB = sessionB.events.listen((event) {
      if (event is Mmrp1PeerReady && !peerB.isCompleted) {
        peerB.complete(event);
      }
    });

    await sessionA.discover();

    expect((await peerA.future.timeout(const Duration(seconds: 1))).mmId, 'mm:b');
    expect((await peerB.future.timeout(const Duration(seconds: 1))).mmId, 'mm:a');
    expect(sessionA.peerReady, isTrue);
    expect(sessionB.peerReady, isTrue);

    await sessionA.probe();
    expect(
      (await pongA.future.timeout(const Duration(seconds: 1))).mmId,
      'mm:b',
    );

    await subA.cancel();
    await subB.cancel();
    await sessionA.close();
    await sessionB.close();
    await transportA.close();
    await transportB.close();
    await linkA.close();
    await linkB.close();
  });
}
