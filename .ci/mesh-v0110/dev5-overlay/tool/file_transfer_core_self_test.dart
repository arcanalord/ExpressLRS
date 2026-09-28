import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';

void main() {
  final abcDigest = M05FileTransferCore.sha256Hex(utf8.encode('abc'));
  if (abcDigest !=
      'ba7816bf8f01cfea414140de5dae2223'
      'b00361a396177a9cb410ff61f20015ad') {
    throw StateError('SHA-256 implementation mismatch: $abcDigest');
  }

  final payload = Uint8List.fromList(
    List<int>.generate(137, (index) => (index * 37 + 11) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'file-test-1',
    fileName: '../camera/photo.jpg',
    mimeType: 'image/jpeg',
    bytes: payload,
    chunkSize: 64,
  );

  if (plan.manifest.fileName != 'photo.jpg') {
    throw StateError('Unsafe file name was not normalized');
  }
  if (plan.manifest.chunkCount != 3 ||
      plan.chunks.map((chunk) => chunk.bytes.length).join(',') != '64,64,9') {
    throw StateError('Chunk split mismatch');
  }

  final roundTripManifest = FileTransferManifest.fromJson(
    jsonDecode(jsonEncode(plan.manifest.toJson())) as Map<String, dynamic>,
  );
  if (roundTripManifest.sha256Hex != plan.manifest.sha256Hex) {
    throw StateError('Manifest JSON round-trip mismatch');
  }

  final missing = M05FileTransferCore.missingChunkIndexes(
    manifest: plan.manifest,
    receivedIndexes: const <int>[0, 2],
  );
  if (missing.length != 1 || missing.single != 1) {
    throw StateError('Resume missing-chunk calculation mismatch: $missing');
  }

  final rebuilt = M05FileTransferCore.reassemble(
    manifest: plan.manifest,
    chunks: <FileTransferChunk>[
      plan.chunks[2],
      plan.chunks[0],
      plan.chunks[1],
    ],
  );
  if (!_bytesEqual(payload, rebuilt)) {
    throw StateError('Reassembled payload mismatch');
  }

  var missingRejected = false;
  try {
    M05FileTransferCore.reassemble(
      manifest: plan.manifest,
      chunks: <FileTransferChunk>[plan.chunks[0], plan.chunks[2]],
    );
  } on StateError {
    missingRejected = true;
  }
  if (!missingRejected) {
    throw StateError('Missing chunks were accepted');
  }

  final corrupted = Uint8List.fromList(plan.chunks[1].bytes);
  corrupted[0] ^= 0xff;
  var corruptionRejected = false;
  try {
    M05FileTransferCore.reassemble(
      manifest: plan.manifest,
      chunks: <FileTransferChunk>[
        plan.chunks[0],
        FileTransferChunk(
          transferId: plan.manifest.transferId,
          index: 1,
          totalChunks: plan.manifest.chunkCount,
          bytes: corrupted,
        ),
        plan.chunks[2],
      ],
    );
  } on FormatException {
    corruptionRejected = true;
  }
  if (!corruptionRejected) {
    throw StateError('Corrupted payload was accepted');
  }

  final empty = M05FileTransferCore.createPlan(
    transferId: 'empty',
    fileName: 'empty.bin',
    mimeType: '',
    bytes: Uint8List(0),
    chunkSize: 64,
  );
  final emptyRebuilt = M05FileTransferCore.reassemble(
    manifest: empty.manifest,
    chunks: const <FileTransferChunk>[],
  );
  if (empty.manifest.chunkCount != 0 ||
      empty.manifest.totalBytes != 0 ||
      emptyRebuilt.isNotEmpty) {
    throw StateError('Empty file semantics mismatch');
  }

  stdout.writeln('MESH_MESSENGER_M05_FILE_TRANSFER_CORE_PASS');
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
