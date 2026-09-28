import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'file_transfer_core.dart';
import 'file_transfer_session.dart';

final class FileTransferPersistence {
  FileTransferPersistence(this.rootDirectory);

  static const schema = 'mesh-messenger-file-receiver-state/v1';
  final Directory rootDirectory;

  Future<void> save(FileTransferReceiverSnapshot snapshot) async {
    M05FileTransferCore.validateManifest(snapshot.manifest);
    final dir = _transferDirectory(snapshot.manifest.transferId);
    await dir.create(recursive: true);

    final indexes = snapshot.receivedChunks.keys.toList()..sort();
    for (final index in indexes) {
      if (index < 0 || index >= snapshot.manifest.chunkCount) {
        throw RangeError.range(
          index,
          0,
          snapshot.manifest.chunkCount - 1,
          'chunk index',
        );
      }
      final bytes = snapshot.receivedChunks[index]!;
      if (bytes.length > snapshot.manifest.chunkSize) {
        throw const FormatException(
          'Persisted chunk exceeds manifest chunk size',
        );
      }
      await _atomicWriteBytes(_chunkFile(dir, index), bytes);
    }

    final state = <String, dynamic>{
      'schema': schema,
      'manifest': snapshot.manifest.toJson(),
      'receivedIndexes': indexes,
    };
    await _atomicWriteBytes(
      File('${dir.path}/state.json'),
      utf8.encode(jsonEncode(state)),
    );
  }

  Future<FileTransferReceiverSnapshot?> load(String transferId) async {
    final dir = _transferDirectory(transferId);
    final stateFile = File('${dir.path}/state.json');
    if (!await stateFile.exists()) return null;

    final decoded = jsonDecode(await stateFile.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schema'] != schema) {
      throw const FormatException('Unsupported persisted M05 receiver state');
    }
    final manifestJson = decoded['manifest'];
    final indexesJson = decoded['receivedIndexes'];
    if (manifestJson is! Map<String, dynamic> || indexesJson is! List) {
      throw const FormatException('Invalid persisted M05 receiver state');
    }
    final manifest = FileTransferManifest.fromJson(manifestJson);
    if (manifest.transferId != transferId) {
      throw const FormatException('Persisted transferId mismatch');
    }

    final chunks = <int, Uint8List>{};
    final seenIndexes = <int>{};
    var totalStored = 0;
    for (final raw in indexesJson) {
      if (raw is! int || raw < 0 || raw >= manifest.chunkCount) {
        throw const FormatException('Invalid persisted chunk index');
      }
      if (!seenIndexes.add(raw)) {
        throw const FormatException('Duplicate persisted chunk index');
      }
      final chunkFile = _chunkFile(dir, raw);
      if (!await chunkFile.exists()) {
        throw StateError('Persisted state references missing chunk $raw');
      }
      final bytes = await chunkFile.readAsBytes();
      final expectedLength = raw == manifest.chunkCount - 1
          ? manifest.totalBytes - raw * manifest.chunkSize
          : manifest.chunkSize;
      if (bytes.length != expectedLength) {
        throw const FormatException('Persisted chunk length mismatch');
      }
      totalStored += bytes.length;
      if (totalStored > manifest.totalBytes) {
        throw const FormatException('Persisted chunks exceed manifest size');
      }
      chunks[raw] = Uint8List.fromList(bytes);
    }

    return FileTransferReceiverSnapshot(
      manifest: manifest,
      receivedChunks: chunks,
    );
  }

  Future<void> clear(String transferId) async {
    final dir = _transferDirectory(transferId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Directory _transferDirectory(String transferId) {
    final key = M05FileTransferCore.sha256Hex(utf8.encode(transferId));
    return Directory('${rootDirectory.path}/m05_$key');
  }

  File _chunkFile(Directory dir, int index) =>
      File('${dir.path}/chunk_${index.toString().padLeft(8, '0')}.bin');

  Future<void> _atomicWriteBytes(File target, List<int> bytes) async {
    final temp = File('${target.path}.tmp');
    if (await temp.exists()) await temp.delete();
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }
}
