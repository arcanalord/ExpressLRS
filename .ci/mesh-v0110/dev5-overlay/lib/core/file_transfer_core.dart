import 'dart:typed_data';

final class FileTransferManifest {
  const FileTransferManifest({
    required this.transferId,
    required this.fileName,
    required this.mimeType,
    required this.totalBytes,
    required this.chunkSize,
    required this.chunkCount,
    required this.sha256Hex,
  });

  static const schema = 'mesh-messenger-file/v1';

  final String transferId;
  final String fileName;
  final String mimeType;
  final int totalBytes;
  final int chunkSize;
  final int chunkCount;
  final String sha256Hex;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schema,
        'transferId': transferId,
        'fileName': fileName,
        'mimeType': mimeType,
        'totalBytes': totalBytes,
        'chunkSize': chunkSize,
        'chunkCount': chunkCount,
        'sha256': sha256Hex,
      };

  static FileTransferManifest fromJson(Map<String, dynamic> json) {
    if (json['schema'] != schema) {
      throw const FormatException('Unsupported file transfer manifest schema');
    }
    final value = FileTransferManifest(
      transferId: json['transferId'] as String,
      fileName: json['fileName'] as String,
      mimeType: json['mimeType'] as String,
      totalBytes: json['totalBytes'] as int,
      chunkSize: json['chunkSize'] as int,
      chunkCount: json['chunkCount'] as int,
      sha256Hex: json['sha256'] as String,
    );
    M05FileTransferCore.validateManifest(value);
    return value;
  }
}

final class FileTransferChunk {
  const FileTransferChunk({
    required this.transferId,
    required this.index,
    required this.totalChunks,
    required this.bytes,
  });

  final String transferId;
  final int index;
  final int totalChunks;
  final Uint8List bytes;
}

final class FileTransferPlan {
  const FileTransferPlan({
    required this.manifest,
    required this.chunks,
  });

  final FileTransferManifest manifest;
  final List<FileTransferChunk> chunks;
}

final class M05FileTransferCore {
  const M05FileTransferCore._();

  static const defaultChunkSize = 1024;
  static const minChunkSize = 64;
  static const maxChunkSize = 16 * 1024;
  static const maxFileBytes = 8 * 1024 * 1024;

  static FileTransferPlan createPlan({
    required String transferId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    int chunkSize = defaultChunkSize,
  }) {
    if (transferId.trim().isEmpty) {
      throw const FormatException('transferId must not be empty');
    }
    if (bytes.length > maxFileBytes) {
      throw RangeError.range(bytes.length, 0, maxFileBytes, 'bytes.length');
    }
    if (chunkSize < minChunkSize || chunkSize > maxChunkSize) {
      throw RangeError.range(
        chunkSize,
        minChunkSize,
        maxChunkSize,
        'chunkSize',
      );
    }

    final safeName = sanitizeFileName(fileName);
    final count = bytes.isEmpty ? 0 : (bytes.length + chunkSize - 1) ~/ chunkSize;
    final manifest = FileTransferManifest(
      transferId: transferId,
      fileName: safeName,
      mimeType: mimeType.trim().isEmpty ? 'application/octet-stream' : mimeType,
      totalBytes: bytes.length,
      chunkSize: chunkSize,
      chunkCount: count,
      sha256Hex: sha256Hex(bytes),
    );

    final chunks = <FileTransferChunk>[];
    for (var index = 0; index < count; index++) {
      final start = index * chunkSize;
      final end = (start + chunkSize < bytes.length)
          ? start + chunkSize
          : bytes.length;
      chunks.add(
        FileTransferChunk(
          transferId: transferId,
          index: index,
          totalChunks: count,
          bytes: Uint8List.fromList(bytes.sublist(start, end)),
        ),
      );
    }

    return FileTransferPlan(
      manifest: manifest,
      chunks: List<FileTransferChunk>.unmodifiable(chunks),
    );
  }

  static List<int> missingChunkIndexes({
    required FileTransferManifest manifest,
    required Iterable<int> receivedIndexes,
  }) {
    validateManifest(manifest);
    final received = receivedIndexes
        .where((index) => index >= 0 && index < manifest.chunkCount)
        .toSet();
    return <int>[
      for (var index = 0; index < manifest.chunkCount; index++)
        if (!received.contains(index)) index,
    ];
  }

  static Uint8List reassemble({
    required FileTransferManifest manifest,
    required Iterable<FileTransferChunk> chunks,
  }) {
    validateManifest(manifest);
    final byIndex = <int, FileTransferChunk>{};

    for (final chunk in chunks) {
      if (chunk.transferId != manifest.transferId) {
        throw const FormatException('Chunk transferId mismatch');
      }
      if (chunk.totalChunks != manifest.chunkCount) {
        throw const FormatException('Chunk count mismatch');
      }
      if (chunk.index < 0 || chunk.index >= manifest.chunkCount) {
        throw RangeError.range(
          chunk.index,
          0,
          manifest.chunkCount - 1,
          'chunk.index',
        );
      }
      final previous = byIndex[chunk.index];
      if (previous != null && !_bytesEqual(previous.bytes, chunk.bytes)) {
        throw const FormatException('Conflicting duplicate chunk');
      }
      byIndex[chunk.index] = chunk;
    }

    final missing = missingChunkIndexes(
      manifest: manifest,
      receivedIndexes: byIndex.keys,
    );
    if (missing.isNotEmpty) {
      throw StateError('Missing chunks: ${missing.join(',')}');
    }

    final builder = BytesBuilder(copy: false);
    for (var index = 0; index < manifest.chunkCount; index++) {
      final chunk = byIndex[index]!;
      if (index < manifest.chunkCount - 1 &&
          chunk.bytes.length != manifest.chunkSize) {
        throw const FormatException('Unexpected non-final chunk size');
      }
      if (chunk.bytes.length > manifest.chunkSize) {
        throw const FormatException('Chunk exceeds manifest chunk size');
      }
      builder.add(chunk.bytes);
    }

    final result = builder.takeBytes();
    if (result.length != manifest.totalBytes) {
      throw const FormatException('Reassembled file size mismatch');
    }
    if (sha256Hex(result) != manifest.sha256Hex) {
      throw const FormatException('Reassembled file SHA-256 mismatch');
    }
    return result;
  }

  static void validateManifest(FileTransferManifest manifest) {
    if (manifest.transferId.trim().isEmpty) {
      throw const FormatException('transferId must not be empty');
    }
    if (manifest.fileName != sanitizeFileName(manifest.fileName)) {
      throw const FormatException('Unsafe file name');
    }
    if (manifest.totalBytes < 0 || manifest.totalBytes > maxFileBytes) {
      throw RangeError.range(
        manifest.totalBytes,
        0,
        maxFileBytes,
        'totalBytes',
      );
    }
    if (manifest.chunkSize < minChunkSize ||
        manifest.chunkSize > maxChunkSize) {
      throw RangeError.range(
        manifest.chunkSize,
        minChunkSize,
        maxChunkSize,
        'chunkSize',
      );
    }
    final expectedCount = manifest.totalBytes == 0
        ? 0
        : (manifest.totalBytes + manifest.chunkSize - 1) ~/ manifest.chunkSize;
    if (manifest.chunkCount != expectedCount) {
      throw const FormatException('Manifest chunk count mismatch');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(manifest.sha256Hex)) {
      throw const FormatException('Invalid SHA-256 digest');
    }
  }

  static String sanitizeFileName(String fileName) {
    final normalized = fileName.trim().replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    var safe = parts.isEmpty ? 'file.bin' : parts.last;
    safe = safe.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_').trim();
    if (safe.isEmpty || safe == '.' || safe == '..') return 'file.bin';
    return safe.length <= 120 ? safe : safe.substring(safe.length - 120);
  }

  static String sha256Hex(List<int> input) {
    final bytes = Uint8List.fromList(input);
    final bitLength = bytes.length * 8;
    final paddedLength = ((bytes.length + 9 + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLength)..setRange(0, bytes.length, bytes);
    padded[bytes.length] = 0x80;

    var remaining = bitLength;
    for (var i = 0; i < 8; i++) {
      padded[padded.length - 1 - i] = remaining & 0xff;
      remaining >>= 8;
    }

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final w = List<int>.filled(64, 0);
    for (var offset = 0; offset < padded.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final p = offset + i * 4;
        w[i] = ((padded[p] << 24) |
                (padded[p + 1] << 16) |
                (padded[p + 2] << 8) |
                padded[p + 3]) &
            0xffffffff;
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^
            _rotr(w[i - 15], 18) ^
            (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^
            _rotr(w[i - 2], 19) ^
            (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + _sha256K[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    return <int>[h0, h1, h2, h3, h4, h5, h6, h7]
        .map((value) => value.toRadixString(16).padLeft(8, '0'))
        .join();
  }

  static int _rotr(int value, int shift) =>
      ((value >> shift) | (value << (32 - shift))) & 0xffffffff;

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

const List<int> _sha256K = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];
