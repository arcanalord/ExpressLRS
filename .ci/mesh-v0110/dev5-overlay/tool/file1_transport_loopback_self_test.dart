import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';
import '../lib/core/file_transfer_protocol.dart';
import '../lib/core/file_transfer_session.dart';
import '../lib/platform/file1_transport_bridge.dart';
import '../lib/platform/m05_transport_qos_adapter.dart';
import '../lib/platform/mm_serial_codec.dart';

Future<void> main() async {
  await _runLoopback(bytes: 20 * 1024, chunkSize: 512);
  await _runLoopback(bytes: 100 * 1024, chunkSize: 1024);
  await _runTransientFinalizeWriteFailure();
  await _runExactFourChunksWithDroppedFinalComplete();
  await _runProactiveFinalCompleteWithoutSenderFinalRequest();
  await _runLinkLossResumeMissingOnly();
  await _runFreshSendAfterLinkRecovery();
  await _runUserPauseResume();
  await _runCancellation();
  stdout.writeln('MESH_MESSENGER_FILE1_FRESH_AFTER_LINK_RECOVERY_PASS');
  stdout.writeln('MESH_MESSENGER_FILE1_USER_PAUSE_PASS');
  stdout.writeln('MESH_MESSENGER_FILE1_LINK_RESUME_PASS');
  stdout.writeln('MESH_MESSENGER_FILE1_VERIFIED_FINAL_ACK_PASS');
  stdout.writeln('MESH_MESSENGER_FILE1_TRANSIENT_FINALIZE_PASS');
  stdout.writeln('MESH_MESSENGER_FILE1_TRANSPORT_LOOPBACK_PASS');
}

Future<void> _runLoopback({required int bytes, required int chunkSize}) async {
  final codecA = MmSerialCodec();
  final codecB = MmSerialCodec();
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  Uint8List? received;
  final progress = <File1TransportProgress>[];

  Future<void> deliver(
    MmSerialCodec encoder,
    MmSerialCodec decoder,
    File1TransportBridge target,
    Uint8List payload,
  ) async {
    final wire = encoder.encodeBinary(
      payload,
      tag: MmSerialCodec.file1BinaryTag,
    );
    for (var offset = 0; offset < wire.length; offset += 37) {
      final end = (offset + 37 < wire.length) ? offset + 37 : wire.length;
      final packets = decoder.feedPackets(
        Uint8List.fromList(wire.sublist(offset, end)),
      );
      for (final packet in packets) {
        if (packet is! MmSerialBinaryPacket ||
            packet.tag != MmSerialCodec.file1BinaryTag) {
          throw StateError('unexpected MM-SERIAL packet');
        }
        await target.handleIncoming(packet.payload);
      }
    }
  }

  late final M05TransportQosAdapter qosA;
  late final M05TransportQosAdapter qosB;
  qosA = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: (payload) => deliver(codecA, codecB, bridgeB, payload),
  );
  qosB = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: (payload) => deliver(codecB, codecA, bridgeA, payload),
  );
  bridgeA = File1TransportBridge(
    sendBytes: qosA.sendFile1,
    onReceived: (_) {},
    onProgress: progress.add,
  );
  bridgeB = File1TransportBridge(
    sendBytes: qosB.sendFile1,
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  final payload = Uint8List.fromList(
    List<int>.generate(bytes, (index) => (index * 43 + bytes) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'loopback-$bytes',
    fileName: 'loopback-$bytes.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: chunkSize,
  );

  await bridgeA.send(plan).timeout(const Duration(seconds: 10));
  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('FILE/1 loopback payload mismatch for $bytes bytes');
  }
  if (codecA.badFrames != 0 || codecB.badFrames != 0) {
    throw StateError('MM-SERIAL bad frames in FILE/1 loopback');
  }
  if (progress.isEmpty ||
      progress.last.state != FileTransferSessionState.completed ||
      progress.last.ackedChunks != progress.last.totalChunks) {
    throw StateError('FILE/1 progress did not reach completed for $bytes');
  }
  var lastAcked = 0;
  for (final event in progress) {
    if (event.ackedChunks < lastAcked) {
      throw StateError('FILE/1 progress regressed for $bytes');
    }
    lastAcked = event.ackedChunks;
  }
  bridgeA.close();
  bridgeB.close();
}

Future<void> _runTransientFinalizeWriteFailure() async {
  await _runFinalizeWriteFailureScenario(
    bytes: 64 * 1024,
    chunkSize: 16 * 1024,
    expectedChunks: 4,
    transferId: 'transient-finalize-4chunks',
  );
  await _runFinalizeWriteFailureScenario(
    bytes: 100 * 1024,
    chunkSize: 16 * 1024,
    expectedChunks: 7,
    transferId: 'transient-finalize-100k',
  );
}

Future<void> _runFinalizeWriteFailureScenario({
  required int bytes,
  required int chunkSize,
  required int expectedChunks,
  required String transferId,
}) async {
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  Uint8List? received;
  var senderCompleteWriteFailed = false;
  var receiverVerifiedAckWriteFailed = false;
  final progress = <File1TransportProgress>[];

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (payload) async {
      final frame = File1Codec.decode(payload);
      if (frame.type == File1FrameType.complete && !senderCompleteWriteFailed) {
        senderCompleteWriteFailed = true;
        throw StateError('simulated transient sender COMPLETE write');
      }
      await bridgeB.handleIncoming(payload);
    },
    onReceived: (_) {},
    onProgress: progress.add,
  );
  bridgeB = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (payload) async {
      final frame = File1Codec.decode(payload);
      if (frame.type == File1FrameType.ack &&
          File1Codec.decodeAck(frame) == File1Codec.verifiedCompleteAckIndex &&
          !receiverVerifiedAckWriteFailed) {
        receiverVerifiedAckWriteFailed = true;
        throw StateError('simulated transient receiver verified ACK write');
      }
      await bridgeA.handleIncoming(payload);
    },
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  final payload = Uint8List.fromList(
    List<int>.generate(bytes, (index) => (index * 17 + 11) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: transferId,
    fileName: '$transferId.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: chunkSize,
  );
  if (plan.manifest.chunkCount != expectedChunks) {
    throw StateError(
      'Unexpected regression fixture chunk count: '
      '${plan.manifest.chunkCount} != $expectedChunks',
    );
  }

  await bridgeA.send(plan).timeout(const Duration(seconds: 8));

  if (!senderCompleteWriteFailed || !receiverVerifiedAckWriteFailed) {
    throw StateError(
      'Transient final-control write failures were not exercised',
    );
  }
  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('Payload mismatch after final COMPLETE retry');
  }
  if (progress.isEmpty ||
      progress.last.state != FileTransferSessionState.completed ||
      progress.last.ackedChunks != expectedChunks ||
      progress.last.totalChunks != expectedChunks) {
    throw StateError(
      '$expectedChunks/$expectedChunks transfer did not recover to completed',
    );
  }

  bridgeA.close();
  bridgeB.close();
}

Future<void> _runLinkLossResumeMissingOnly() async {
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  Uint8List? received;
  var failedOnce = false;
  final chunkSendCounts = <int, int>{};

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (payload) async {
      final frame = File1Codec.decode(payload);
      if (frame.type == File1FrameType.chunk) {
        final chunk = File1Codec.decodeChunk(frame);
        chunkSendCounts[chunk.index] = (chunkSendCounts[chunk.index] ?? 0) + 1;
        if (chunk.index == 8 && !failedOnce) {
          failedOnce = true;
          throw StateError('simulated LR24 detach');
        }
      }
      await bridgeB.handleIncoming(payload);
    },
    onReceived: (_) {},
  );
  bridgeB = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: bridgeA.handleIncoming,
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  final payload = Uint8List.fromList(
    List<int>.generate(100 * 1024, (index) => (index * 29 + 5) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'u1-style-link-resume-100k',
    fileName: 'resume-100k.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: 1024,
  );

  final future = bridgeA.send(plan);
  for (var i = 0; i < 200 && !failedOnce; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  if (!failedOnce) {
    throw StateError('link loss fixture was not exercised');
  }
  await Future<void>.delayed(const Duration(milliseconds: 30));
  bridgeA.resumeAfterLink();
  await future.timeout(const Duration(seconds: 10));

  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('resume payload mismatch');
  }
  for (var index = 0; index < 8; index++) {
    if (chunkSendCounts[index] != 1) {
      throw StateError(
        'resume resent already acknowledged chunk ' +
            index.toString() +
            ' count=' +
            (chunkSendCounts[index] ?? 0).toString(),
      );
    }
  }
  if ((chunkSendCounts[8] ?? 0) < 2) {
    throw StateError('missing chunk 8 was not retried after resume');
  }

  bridgeA.close();
  bridgeB.close();
}

Future<void> _runUserPauseResume() async {
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  final progress = <File1TransportProgress>[];
  final chunkSendCounts = <int, int>{};
  Uint8List? received;

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 3),
    sendBytes: (payload) async {
      final frame = File1Codec.decode(payload);
      if (frame.type == File1FrameType.chunk) {
        final chunk = File1Codec.decodeChunk(frame);
        chunkSendCounts[chunk.index] = (chunkSendCounts[chunk.index] ?? 0) + 1;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await bridgeB.handleIncoming(payload);
    },
    onReceived: (_) {},
    onProgress: progress.add,
  );
  bridgeB = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 3),
    sendBytes: bridgeA.handleIncoming,
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  final payload = Uint8List.fromList(
    List<int>.generate(24 * 1024, (index) => (index * 13 + 7) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'user-pause-resume',
    fileName: 'pause-resume.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: 1024,
  );

  final future = bridgeA.send(plan);
  var ackedBeforePause = 0;
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 3));
    if (progress.isNotEmpty) ackedBeforePause = progress.last.ackedChunks;
    if (ackedBeforePause >= 3 && ackedBeforePause < plan.manifest.chunkCount)
      break;
  }
  if (ackedBeforePause < 3)
    throw StateError('user pause fixture did not make progress');
  if (!bridgeA.pauseByUser(plan.manifest.transferId))
    throw StateError('user pause returned false');
  await Future<void>.delayed(const Duration(milliseconds: 25));
  if (progress
      .where((e) => e.state == FileTransferSessionState.pausedUser)
      .isEmpty) {
    throw StateError('pausedUser progress state missing');
  }
  final sentWhilePaused = chunkSendCounts.values.fold<int>(0, (a, b) => a + b);
  await Future<void>.delayed(const Duration(milliseconds: 25));
  final sentStillPaused = chunkSendCounts.values.fold<int>(0, (a, b) => a + b);
  if (sentStillPaused != sentWhilePaused) {
    throw StateError('FILE/1 continued sending while user-paused');
  }

  if (!bridgeA.resumeByUser(plan.manifest.transferId))
    throw StateError('user resume returned false');
  await future.timeout(const Duration(seconds: 8));
  final result = received;
  if (result == null || !_same(payload, result))
    throw StateError('user pause/resume payload mismatch');
  for (var index = 0; index < ackedBeforePause; index++) {
    if (chunkSendCounts[index] != 1) {
      throw StateError(
        'user resume resent acknowledged chunk $index count=${chunkSendCounts[index] ?? 0}',
      );
    }
  }
  if (progress.last.state != FileTransferSessionState.completed) {
    throw StateError('user pause/resume did not complete');
  }
  bridgeA.close();
  bridgeB.close();
}

Future<void> _runFreshSendAfterLinkRecovery() async {
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  Uint8List? received;

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (payload) => bridgeB.handleIncoming(payload),
    onReceived: (_) {},
  );
  bridgeB = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (payload) => bridgeA.handleIncoming(payload),
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  // Reproduce the rc7 physical failure: transport connect marks FILE/1
  // unavailable before any sender exists. Peer discovery must make a later
  // first transfer possible.
  bridgeA.pauseForLinkLoss();
  bridgeA.resumeAfterLink();

  final payload = Uint8List.fromList(
    List<int>.generate(8192, (index) => (index * 13 + 5) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'fresh-after-link-recovery',
    fileName: 'fresh.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: 1024,
  );

  await bridgeA.send(plan).timeout(const Duration(seconds: 10));
  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('fresh send after link recovery payload mismatch');
  }

  bridgeA.close();
  bridgeB.close();
}

Future<void> _runCancellation() async {
  final progress = <File1TransportProgress>[];
  final bridge = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (_) async {
      // Drop frames deliberately so the sender remains active.
    },
    onReceived: (_) {},
    onProgress: progress.add,
  );
  final payload = Uint8List.fromList(
    List<int>.generate(4096, (index) => index & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'cancel-test',
    fileName: 'cancel.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: 512,
  );

  final future = bridge.send(plan);
  await Future<void>.delayed(const Duration(milliseconds: 25));
  final cancelled = await bridge.cancel(plan.manifest.transferId);
  if (!cancelled) throw StateError('FILE/1 cancel returned false');

  var completedWithError = false;
  try {
    await future;
  } catch (_) {
    completedWithError = true;
  }
  if (!completedWithError) {
    throw StateError('FILE/1 cancelled transfer did not terminate future');
  }
  if (progress.isEmpty ||
      progress.last.state != FileTransferSessionState.cancelled) {
    throw StateError('FILE/1 cancel progress state missing');
  }
  bridge.close();
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> _runExactFourChunksWithDroppedFinalComplete() async {
  final codecA = MmSerialCodec();
  final codecB = MmSerialCodec();
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  var dropFirstVerifiedAck = true;
  Uint8List? received;
  final progress = <File1TransportProgress>[];

  Future<void> deliver(
    MmSerialCodec encoder,
    MmSerialCodec decoder,
    File1TransportBridge target,
    Uint8List payload, {
    bool dropVerifiedAckResponse = false,
  }) async {
    final decoded = File1Codec.decode(payload);
    if (dropVerifiedAckResponse &&
        decoded.type == File1FrameType.ack &&
        File1Codec.decodeAck(decoded) == File1Codec.verifiedCompleteAckIndex &&
        dropFirstVerifiedAck) {
      dropFirstVerifiedAck = false;
      return;
    }
    final wire = encoder.encodeBinary(
      payload,
      tag: MmSerialCodec.file1BinaryTag,
    );
    final packets = decoder.feedPackets(wire);
    for (final packet in packets) {
      if (packet is! MmSerialBinaryPacket ||
          packet.tag != MmSerialCodec.file1BinaryTag) {
        throw StateError('unexpected MM-SERIAL packet');
      }
      await target.handleIncoming(packet.payload);
    }
  }

  late final M05TransportQosAdapter qosA;
  late final M05TransportQosAdapter qosB;
  qosA = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: (payload) => deliver(codecA, codecB, bridgeB, payload),
  );
  qosB = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: (payload) => deliver(
      codecB,
      codecA,
      bridgeA,
      payload,
      dropVerifiedAckResponse: true,
    ),
  );

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: qosA.sendFile1,
    onReceived: (_) {},
    onProgress: progress.add,
  );
  bridgeB = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: qosB.sendFile1,
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  const chunkSize = 512;
  final payload = Uint8List.fromList(
    List<int>.generate(chunkSize * 4, (index) => (index * 17 + 3) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'exact-four-final-retry',
    fileName: 'four-chunks.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: chunkSize,
  );
  if (plan.manifest.chunkCount != 4) {
    throw StateError('regression fixture must contain exactly 4 chunks');
  }

  await bridgeA.send(plan).timeout(const Duration(seconds: 10));
  if (dropFirstVerifiedAck) {
    throw StateError('verified final ACK response was not dropped');
  }
  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('exact-four receiver payload mismatch');
  }
  if (progress.isEmpty ||
      progress.last.state != FileTransferSessionState.completed ||
      progress.last.ackedChunks != 4) {
    throw StateError('exact-four sender did not complete after 4/4 ACKs');
  }

  bridgeA.close();
  bridgeB.close();
}

Future<void> _runProactiveFinalCompleteWithoutSenderFinalRequest() async {
  final codecA = MmSerialCodec();
  final codecB = MmSerialCodec();
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  Uint8List? received;
  var senderExplicitCompleteCount = 0;
  final progress = <File1TransportProgress>[];

  Future<void> deliverAtoB(Uint8List payload) async {
    final decoded = File1Codec.decode(payload);
    if (decoded.type == File1FrameType.complete) {
      senderExplicitCompleteCount++;
      // Deliberately drop every sender COMPLETE request. The receiver must
      // finish proactively after receiving/verifying the last chunk.
      return;
    }
    final wire = codecA.encodeBinary(
      payload,
      tag: MmSerialCodec.file1BinaryTag,
    );
    for (final packet in codecB.feedPackets(wire)) {
      if (packet is! MmSerialBinaryPacket) {
        throw StateError('unexpected A->B packet');
      }
      await bridgeB.handleIncoming(packet.payload);
    }
  }

  Future<void> deliverBtoA(Uint8List payload) async {
    final wire = codecB.encodeBinary(
      payload,
      tag: MmSerialCodec.file1BinaryTag,
    );
    for (final packet in codecA.feedPackets(wire)) {
      if (packet is! MmSerialBinaryPacket) {
        throw StateError('unexpected B->A packet');
      }
      await bridgeA.handleIncoming(packet.payload);
    }
  }

  final qosA = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: deliverAtoB,
  );
  final qosB = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: deliverBtoA,
  );

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: qosA.sendFile1,
    onReceived: (_) {},
    onProgress: progress.add,
  );
  bridgeB = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: qosB.sendFile1,
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  const chunkSize = 4096;
  final payload = Uint8List.fromList(
    List<int>.generate(10219, (index) => (index * 31 + 7) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'proactive-final-3-chunks',
    fileName: 'low_voltage_specialist.html',
    mimeType: 'text/html',
    bytes: payload,
    chunkSize: chunkSize,
  );
  if (plan.manifest.chunkCount != 3) {
    throw StateError('fixture must contain exactly 3 chunks');
  }

  await bridgeA.send(plan).timeout(const Duration(seconds: 10));

  if (senderExplicitCompleteCount != 0) {
    throw StateError(
      'sender should complete from receiver proactive COMPLETE before polling explicit final request',
    );
  }
  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('proactive-final payload mismatch');
  }
  if (progress.isEmpty ||
      progress.last.state != FileTransferSessionState.completed ||
      progress.last.ackedChunks != 3) {
    throw StateError('proactive-final did not complete at 3/3');
  }

  bridgeA.close();
  bridgeB.close();
}
