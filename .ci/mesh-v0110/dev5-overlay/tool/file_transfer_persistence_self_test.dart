import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';
import '../lib/core/file_transfer_persistence.dart';
import '../lib/core/file_transfer_protocol.dart';
import '../lib/core/file_transfer_session.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    await _child(args);
    return;
  }
  await _run(bytes: 20 * 1024, chunkSize: 512, persistedChunks: 11);
  await _run(bytes: 100 * 1024, chunkSize: 1024, persistedChunks: 37);
  stdout.writeln('MESH_MESSENGER_M05_PERSISTENCE_RESTART_PASS');
}

Future<void> _run({
  required int bytes,
  required int chunkSize,
  required int persistedChunks,
}) async {
  final root = await Directory.systemTemp.createTemp('m05_restart_');
  try {
    final common = <String>[
      root.path,
      bytes.toString(),
      chunkSize.toString(),
      persistedChunks.toString(),
    ];
    final first = await Process.run(Platform.resolvedExecutable, <String>[
      Platform.script.toFilePath(),
      'write',
      ...common,
    ]);
    if (first.exitCode != 0) throw StateError('writer failed: ${first.stderr}');
    final second = await Process.run(Platform.resolvedExecutable, <String>[
      Platform.script.toFilePath(),
      'resume',
      ...common,
    ]);
    if (second.exitCode != 0)
      throw StateError('resume failed: ${second.stderr}');
    if (!second.stdout.toString().contains('CHILD_RESUME_PASS'))
      throw StateError('resume marker missing');
  } finally {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _child(List<String> args) async {
  final mode = args[0];
  final root = Directory(args[1]);
  final bytes = int.parse(args[2]);
  final chunkSize = int.parse(args[3]);
  final persistedChunks = int.parse(args[4]);
  final payload = Uint8List.fromList(
    List<int>.generate(bytes, (i) => (i * 31 + bytes) & 0xff),
  );
  final transferId = 'restart-$bytes';
  final plan = M05FileTransferCore.createPlan(
    transferId: transferId,
    fileName: 'restart-$bytes.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: chunkSize,
  );
  final persistence = FileTransferPersistence(root);

  if (mode == 'write') {
    final receiver = FileTransferReceiverSession();
    receiver.onFrame(File1Codec.manifest(plan.manifest));
    for (var i = 0; i < persistedChunks; i++) {
      if (i == 3) continue;
      receiver.onFrame(File1Codec.chunk(plan.chunks[i]));
    }
    await persistence.save(receiver.snapshot());
    stdout.writeln('CHILD_WRITE_PASS');
    return;
  }

  if (mode == 'resume') {
    final snapshot = await persistence.load(transferId);
    if (snapshot == null)
      throw StateError('snapshot missing after process restart');
    final receiver = FileTransferReceiverSession.restore(snapshot);
    final missingBefore = receiver.missingIndexes();
    if (!missingBefore.contains(3))
      throw StateError('deliberately missing chunk 3 not detected');
    for (final index in missingBefore) {
      receiver.onFrame(File1Codec.chunk(plan.chunks[index]));
    }
    final responses = receiver.onFrame(File1Codec.complete(transferId));
    if (responses.length != 1 ||
        responses.single.type != File1FrameType.complete) {
      throw StateError('receiver did not complete after restart');
    }
    final result = receiver.completedBytes;
    if (result == null || !_bytesEqual(result, payload))
      throw StateError('payload mismatch after restart');
    await persistence.clear(transferId);
    if (await persistence.load(transferId) != null)
      throw StateError('clear did not remove persisted state');
    stdout.writeln('CHILD_RESUME_PASS');
    return;
  }
  throw ArgumentError.value(mode, 'mode');
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
