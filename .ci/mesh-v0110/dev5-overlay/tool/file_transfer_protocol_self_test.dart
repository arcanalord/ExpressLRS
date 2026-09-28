import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';
import '../lib/core/file_transfer_protocol.dart';

void main() {
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

  stdout.writeln('MESH_MESSENGER_FILE1_PROTOCOL_PASS');
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
