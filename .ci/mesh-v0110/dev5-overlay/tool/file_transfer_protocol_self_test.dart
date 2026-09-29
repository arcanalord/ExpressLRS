import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';
import '../lib/core/file_transfer_protocol.dart';
import '../lib/platform/file1_transport_bridge.dart';

Future<void> main() async {
  final payload = Uint8List.fromList(
    List<int>.generate(211, (index) => (index * 19 + 7) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'wire-1',
    fileName: 'photo.jpg',
    mimeType: 'image/jpeg',
    bytes: payload,
    chunkSize: 64,
  );

  final manifestFrame = File1Codec.decode(
    File1Codec.encode(File1Codec.manifest(plan.manifest)),
  );
  final manifest = File1Codec.decodeManifest(manifestFrame);
  if (manifest.sha256Hex != plan.manifest.sha256Hex) {
    throw StateError('Manifest FILE/1 round-trip failed');
  }

  final decodedChunks = <FileTransferChunk>[];
  for (final chunk in plan.chunks.reversed) {
    final frame = File1Codec.decode(File1Codec.encode(File1Codec.chunk(chunk)));
    decodedChunks.add(File1Codec.decodeChunk(frame));
  }
  final rebuilt = M05FileTransferCore.reassemble(
    manifest: manifest,
    chunks: decodedChunks,
  );
  if (!_bytesEqual(payload, rebuilt)) {
    throw StateError('FILE/1 chunk round-trip failed');
  }

  final missingFrame = File1Codec.decode(
    File1Codec.encode(File1Codec.missing('wire-1', <int>[3, 1, 1, 2])),
  );
  final missing = File1Codec.decodeMissing(missingFrame);
  if (missing.join(',') != '1,2,3') {
    throw StateError('FILE/1 missing frame mismatch');
  }

  final ack = File1Codec.decodeAck(
    File1Codec.decode(File1Codec.encode(File1Codec.ack('wire-1', 7))),
  );
  if (ack != 7) {
    throw StateError('FILE/1 ACK mismatch');
  }

  final verifiedAck = File1Codec.decodeAck(
    File1Codec.decode(
      File1Codec.encode(File1Codec.verifiedCompleteAck('wire-1')),
    ),
  );
  if (verifiedAck != File1Codec.verifiedCompleteAckIndex) {
    throw StateError('FILE/1 verified COMPLETE ACK mismatch');
  }

  final errorText = File1Codec.decodeError(
    File1Codec.decode(
      File1Codec.encode(File1Codec.error('wire-1', 'retry later')),
    ),
  );
  if (errorText != 'retry later') {
    throw StateError('FILE/1 error frame mismatch');
  }

  final goodChunkBytes = File1Codec.encode(File1Codec.chunk(plan.chunks.first));
  final corrupt = Uint8List.fromList(goodChunkBytes);
  corrupt[corrupt.length - 1] ^= 0x01;
  var crcRejected = false;
  try {
    File1Codec.decodeChunk(File1Codec.decode(corrupt));
  } on FormatException {
    crcRejected = true;
  }
  if (!crcRejected) {
    throw StateError('FILE/1 corrupt chunk was accepted');
  }

  final crcVector = File1Codec.crc32('123456789'.codeUnits);
  if (crcVector != 0xcbf43926) {
    throw StateError('CRC32 implementation mismatch');
  }

  final retryPlan = M05FileTransferCore.createPlan(
    transferId: 'wire-final-retry',
    fileName: 'retry.bin',
    mimeType: 'application/octet-stream',
    bytes: Uint8List.fromList(
      List<int>.generate(93, (index) => (index * 13 + 5) & 0xff),
    ),
    chunkSize: 64,
  );
  var receiverDeliveries = 0;
  var droppedFirstVerifiedAck = false;
  late File1TransportBridge senderBridge;
  late File1TransportBridge receiverBridge;
  senderBridge = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (bytes) => receiverBridge.handleIncoming(bytes),
    onReceived: (_) {},
  );
  receiverBridge = File1TransportBridge(
    tickInterval: const Duration(milliseconds: 5),
    sendBytes: (bytes) async {
      final response = File1Codec.decode(bytes);
      if (!droppedFirstVerifiedAck &&
          response.type == File1FrameType.ack &&
          File1Codec.decodeAck(response) ==
              File1Codec.verifiedCompleteAckIndex) {
        droppedFirstVerifiedAck = true;
        return;
      }
      await senderBridge.handleIncoming(bytes);
    },
    onReceived: (_) => receiverDeliveries++,
  );
  try {
    await senderBridge.send(retryPlan).timeout(const Duration(seconds: 3));
    if (!droppedFirstVerifiedAck || receiverDeliveries != 1) {
      throw StateError(
        'FILE/1 verified-final ACK fallback/idempotence failed: '
        'dropped=$droppedFirstVerifiedAck deliveries=$receiverDeliveries',
      );
    }
  } finally {
    senderBridge.close();
    receiverBridge.close();
  }

  stdout.writeln('MESH_MESSENGER_FILE1_PROTOCOL_PASS');
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
