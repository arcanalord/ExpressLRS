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
  await _runCancellation();
  stdout.writeln('MESH_MESSENGER_FILE1_TRANSIENT_FINALIZE_PASS');
  stdout.writeln('MESH_MESSENGER_FILE1_TRANSPORT_LOOPBACK_PASS');
}

Future<void> _runLoopback({
  required int bytes,
  required int chunkSize,
}) async {
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
  var receiverCompleteWriteFailed = false;
  final progress = <File1TransportProgress>[];

  bridgeA = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (payload) async {
      final frame = File1Codec.decode(payload);
      if (frame.type == File1FrameType.complete &&
          !senderCompleteWriteFailed) {
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
      if (frame.type == File1FrameType.complete &&
          !receiverCompleteWriteFailed) {
        receiverCompleteWriteFailed = true;
        throw StateError('simulated transient receiver COMPLETE write');
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

  if (!senderCompleteWriteFailed || !receiverCompleteWriteFailed) {
    throw StateError('Transient COMPLETE write failures were not exercised');
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
