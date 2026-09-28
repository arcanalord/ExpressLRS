import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';
import '../lib/core/file_transfer_protocol.dart';
import '../lib/core/file_transfer_session.dart';

void main() {
  _runScenario(bytes: 20 * 1024, chunkSize: 512, interruptAtAcked: 11);
  _runScenario(bytes: 100 * 1024, chunkSize: 1024, interruptAtAcked: 37);
  stdout.writeln('MESH_MESSENGER_M05_TRANSFER_SESSION_PASS');
}

void _runScenario({
  required int bytes,
  required int chunkSize,
  required int interruptAtAcked,
}) {
  final payload = Uint8List.fromList(
    List<int>.generate(bytes, (index) => (index * 29 + bytes) & 0xff),
  );
  final transferId = 'session-$bytes';
  final plan = M05FileTransferCore.createPlan(
    transferId: transferId,
    fileName: 'payload-$bytes.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: chunkSize,
  );
  final sender = FileTransferSenderSession(
    plan: plan,
    windowSize: 5,
    ackTimeoutMs: 120,
    maxRetries: 12,
  );
  var receiver = FileTransferReceiverSession();
  var now = 0;
  var interrupted = false;
  var droppedChunkOnce = false;
  var droppedAckOnce = false;
  var safety = 0;

  while (!sender.isTerminal && safety++ < 20000) {
    final outbound = sender.poll(now);
    for (final frame in outbound) {
      if (frame.type == File1FrameType.chunk) {
        final chunk = File1Codec.decodeChunk(frame);
        if (!droppedChunkOnce && chunk.index == 3) {
          droppedChunkOnce = true;
          continue;
        }
      }
      final responses = receiver.onFrame(frame);
      for (final response in responses) {
        if (response.type == File1FrameType.ack) {
          final ack = File1Codec.decodeAck(response);
          if (!droppedAckOnce && ack == 7) {
            droppedAckOnce = true;
            continue;
          }
        }
        sender.onFrame(response, now);
      }
    }

    if (!interrupted && sender.ackedChunkCount >= interruptAtAcked) {
      final snapshot = receiver.snapshot();
      receiver = FileTransferReceiverSession.restore(snapshot);
      final missing = receiver.missingIndexes();
      sender.onFrame(File1Codec.missing(transferId, missing), now);
      interrupted = true;
    }

    now += 25;
  }

  if (sender.state != FileTransferSessionState.completed) {
    throw StateError('Sender did not complete $bytes bytes: ${sender.state}');
  }
  final result = receiver.completedBytes;
  if (result == null || !_bytesEqual(payload, result)) {
    throw StateError('Receiver payload mismatch for $bytes bytes');
  }
  if (!droppedChunkOnce || !droppedAckOnce || !interrupted) {
    throw StateError(
      'Failure/recovery paths were not exercised for $bytes bytes',
    );
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
