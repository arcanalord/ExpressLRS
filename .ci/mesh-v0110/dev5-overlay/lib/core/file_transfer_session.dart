import 'dart:collection';
import 'dart:typed_data';

import 'file_transfer_core.dart';
import 'file_transfer_protocol.dart';

enum FileTransferSessionState {
  idle,
  sendingManifest,
  sending,
  waiting,
  pausedLink,
  completed,
  failed,
  cancelled,
}

final class FileTransferSenderSession {
  FileTransferSenderSession({
    required this.plan,
    this.windowSize = 1,
    this.ackTimeoutMs = 3000,
    this.maxRetries = 8,
  }) {
    if (windowSize <= 0) throw RangeError.value(windowSize, 'windowSize');
    if (ackTimeoutMs <= 0) throw RangeError.value(ackTimeoutMs, 'ackTimeoutMs');
    if (maxRetries < 0) throw RangeError.value(maxRetries, 'maxRetries');
    _pending.addAll(
      List<int>.generate(plan.manifest.chunkCount, (index) => index),
    );
  }

  final FileTransferPlan plan;
  final int windowSize;
  final int ackTimeoutMs;
  final int maxRetries;

  FileTransferSessionState state = FileTransferSessionState.idle;
  bool _manifestAcked = false;
  bool _pausedForLink = false;
  bool _completeSent = false;
  int _completeAttempts = 0;
  String? failureReason;
  int _lastCompleteSentAtMs = -0x7fffffff;
  final Queue<int> _pending = Queue<int>();
  final Set<int> _acked = <int>{};
  final Map<int, int> _lastSentAtMs = <int, int>{};
  final Map<int, int> _attempts = <int, int>{};

  int get ackedChunkCount => _acked.length;
  int get totalChunkCount => plan.manifest.chunkCount;
  double get progress =>
      totalChunkCount == 0 ? 1 : ackedChunkCount / totalChunkCount;
  bool get isTerminal =>
      state == FileTransferSessionState.completed ||
      state == FileTransferSessionState.failed ||
      state == FileTransferSessionState.cancelled;

  List<File1Frame> poll(int nowMs) {
    if (isTerminal || _pausedForLink) return const <File1Frame>[];
    if (!_manifestAcked) {
      state = FileTransferSessionState.sendingManifest;
      return <File1Frame>[File1Codec.manifest(plan.manifest)];
    }

    _requeueTimedOut(nowMs);
    if (state == FileTransferSessionState.failed) return const <File1Frame>[];

    final frames = <File1Frame>[];
    final inFlight = _lastSentAtMs.keys
        .where((i) => !_acked.contains(i))
        .length;
    var capacity = windowSize - inFlight;
    while (capacity > 0 && _pending.isNotEmpty) {
      final index = _pending.removeFirst();
      if (_acked.contains(index) || _lastSentAtMs.containsKey(index)) continue;
      final attempts = (_attempts[index] ?? 0) + 1;
      if (attempts > maxRetries + 1) {
        failureReason = 'chunk-retry-exhausted:' + index.toString();
        state = FileTransferSessionState.failed;
        return frames;
      }
      _attempts[index] = attempts;
      _lastSentAtMs[index] = nowMs;
      frames.add(File1Codec.chunk(plan.chunks[index]));
      capacity--;
    }

    if (_acked.length == totalChunkCount) {
      final shouldSendComplete = !_completeSent ||
          nowMs - _lastCompleteSentAtMs >= ackTimeoutMs;
      if (shouldSendComplete) {
        final attempts = _completeAttempts + 1;
        if (attempts > maxRetries + 1) {
          failureReason = 'final-confirmation-timeout';
          state = FileTransferSessionState.failed;
          return frames;
        }
        _completeAttempts = attempts;
        _completeSent = true;
        _lastCompleteSentAtMs = nowMs;
        state = FileTransferSessionState.waiting;
        frames.add(File1Codec.complete(plan.manifest.transferId));
      } else {
        state = FileTransferSessionState.waiting;
      }
    } else if (frames.isNotEmpty) {
      state = FileTransferSessionState.sending;
    } else {
      state = FileTransferSessionState.waiting;
    }
    return frames;
  }

  void onFrame(File1Frame frame, int nowMs) {
    if (frame.transferId != plan.manifest.transferId || isTerminal) return;
    switch (frame.type) {
      case File1FrameType.ack:
        final index = File1Codec.decodeAck(frame);
        if (index == File1Codec.manifestAckIndex) {
          _manifestAcked = true;
          state = FileTransferSessionState.sending;
          return;
        }
        if (index == File1Codec.verifiedCompleteAckIndex) {
          _acked.addAll(List<int>.generate(totalChunkCount, (i) => i));
          _lastSentAtMs.clear();
          failureReason = null;
          state = FileTransferSessionState.completed;
          return;
        }
        if (index >= 0 && index < totalChunkCount) {
          _acked.add(index);
          _lastSentAtMs.remove(index);
        }
      case File1FrameType.missing:
        final missing = File1Codec.decodeMissing(frame)
            .where((index) => index >= 0 && index < totalChunkCount)
            .toSet();
        _acked
          ..clear()
          ..addAll(
            List<int>.generate(totalChunkCount, (index) => index)
                .where((index) => !missing.contains(index)),
          );
        _pending
          ..clear()
          ..addAll(missing.toList()..sort());
        _lastSentAtMs.clear();
        _attempts.removeWhere((index, _) => missing.contains(index));
        _completeSent = false;
        _completeAttempts = 0;
        _lastCompleteSentAtMs = -0x7fffffff;
        failureReason = null;
        state = missing.isEmpty
            ? FileTransferSessionState.waiting
            : FileTransferSessionState.sending;
      case File1FrameType.complete:
        failureReason = null;
        state = FileTransferSessionState.completed;
      case File1FrameType.error:
        failureReason = File1Codec.decodeError(frame);
        state = FileTransferSessionState.failed;
      case File1FrameType.manifest:
      case File1FrameType.chunk:
        break;
    }
  }

  void pauseForLinkLoss() {
    if (isTerminal || _pausedForLink) return;
    _pausedForLink = true;
    state = FileTransferSessionState.pausedLink;
    failureReason = 'waiting-link';
  }

  void resumeAfterLink() {
    if (isTerminal || !_pausedForLink) return;
    _pausedForLink = false;
    _manifestAcked = false;
    _completeSent = false;
    _completeAttempts = 0;
    _lastCompleteSentAtMs = -0x7fffffff;
    _lastSentAtMs.clear();
    _attempts.removeWhere((index, _) => !_acked.contains(index));
    _pending
      ..clear()
      ..addAll(
        List<int>.generate(totalChunkCount, (index) => index)
            .where((index) => !_acked.contains(index)),
      );
    failureReason = null;
    state = FileTransferSessionState.sendingManifest;
  }

  void cancel() {
    if (!isTerminal) {
      _pausedForLink = false;
      failureReason = 'cancelled';
      state = FileTransferSessionState.cancelled;
    }
  }

  void _requeueTimedOut(int nowMs) {
    final expired = <int>[];
    for (final entry in _lastSentAtMs.entries) {
      if (!_acked.contains(entry.key) && nowMs - entry.value >= ackTimeoutMs) {
        expired.add(entry.key);
      }
    }
    for (final index in expired) {
      _lastSentAtMs.remove(index);
      if ((_attempts[index] ?? 0) > maxRetries) {
        failureReason = 'chunk-retry-exhausted:' + index.toString();
        state = FileTransferSessionState.failed;
        return;
      }
      if (!_pending.contains(index)) _pending.add(index);
    }
  }
}

final class FileTransferReceiverSnapshot {
  const FileTransferReceiverSnapshot({
    required this.manifest,
    required this.receivedChunks,
  });

  final FileTransferManifest manifest;
  final Map<int, Uint8List> receivedChunks;
}

final class FileTransferReceiverSession {
  FileTransferReceiverSession({
    this.maxStoredBytes = M05FileTransferCore.maxFileBytes,
  });

  FileTransferReceiverSession.restore(
    FileTransferReceiverSnapshot snapshot, {
    this.maxStoredBytes = M05FileTransferCore.maxFileBytes,
  }) {
    manifest = snapshot.manifest;
    for (final entry in snapshot.receivedChunks.entries) {
      _chunks[entry.key] = FileTransferChunk(
        transferId: snapshot.manifest.transferId,
        index: entry.key,
        totalChunks: snapshot.manifest.chunkCount,
        bytes: Uint8List.fromList(entry.value),
      );
    }
  }

  final int maxStoredBytes;
  FileTransferManifest? manifest;
  final Map<int, FileTransferChunk> _chunks = <int, FileTransferChunk>{};
  Uint8List? completedBytes;

  int get receivedChunkCount => _chunks.length;
  bool get isComplete => completedBytes != null;

  List<File1Frame> onFrame(File1Frame frame) {
    switch (frame.type) {
      case File1FrameType.manifest:
        final incoming = File1Codec.decodeManifest(frame);
        if (incoming.totalBytes > maxStoredBytes) {
          return <File1Frame>[
            File1Codec.error(frame.transferId, 'storage-limit'),
          ];
        }
        if (manifest != null && manifest!.transferId != incoming.transferId) {
          return <File1Frame>[File1Codec.error(frame.transferId, 'busy')];
        }
        manifest = incoming;
        final missing = missingIndexes();
        return <File1Frame>[
          File1Codec.ack(frame.transferId, File1Codec.manifestAckIndex),
          File1Codec.missing(frame.transferId, missing),
        ];
      case File1FrameType.chunk:
        final current = manifest;
        if (current == null) {
          return <File1Frame>[
            File1Codec.error(frame.transferId, 'manifest-required'),
          ];
        }
        FileTransferChunk chunk;
        try {
          chunk = File1Codec.decodeChunk(frame);
        } on FormatException {
          return <File1Frame>[
            File1Codec.missing(frame.transferId, missingIndexes()),
          ];
        }
        if (chunk.totalChunks != current.chunkCount ||
            chunk.index >= current.chunkCount) {
          return <File1Frame>[
            File1Codec.error(frame.transferId, 'chunk-range'),
          ];
        }
        _chunks.putIfAbsent(chunk.index, () => chunk);
        final ack = File1Codec.ack(frame.transferId, chunk.index);
        final missingAfterChunk = M05FileTransferCore.missingChunkIndexes(
          manifest: current,
          receivedIndexes: _chunks.keys,
        );
        if (missingAfterChunk.isNotEmpty) {
          return <File1Frame>[ack];
        }
        try {
          completedBytes = M05FileTransferCore.reassemble(
            manifest: current,
            chunks: _chunks.values,
          );
        } on Object {
          return <File1Frame>[
            ack,
            File1Codec.error(frame.transferId, 'integrity'),
          ];
        }
        // Always acknowledge the final chunk itself, then send the verified
        // final sentinel. If the sentinel is lost, the sender still reaches
        // N/N and can use its explicit COMPLETE fallback against the receiver
        // tombstone. This avoids retransmitting the last chunk into a closed
        // receiver session and getting a misleading manifest-required error.
        return <File1Frame>[
          ack,
          File1Codec.verifiedCompleteAck(frame.transferId),
        ];
      case File1FrameType.complete:
        final current = manifest;
        if (current == null) {
          return <File1Frame>[
            File1Codec.error(frame.transferId, 'manifest-required'),
          ];
        }
        final missing = M05FileTransferCore.missingChunkIndexes(
          manifest: current,
          receivedIndexes: _chunks.keys,
        );
        if (missing.isNotEmpty) {
          return <File1Frame>[File1Codec.missing(frame.transferId, missing)];
        }
        try {
          completedBytes = M05FileTransferCore.reassemble(
            manifest: current,
            chunks: _chunks.values,
          );
        } on Object {
          return <File1Frame>[File1Codec.error(frame.transferId, 'integrity')];
        }
        return <File1Frame>[File1Codec.complete(frame.transferId)];
      case File1FrameType.ack:
      case File1FrameType.missing:
      case File1FrameType.error:
        return const <File1Frame>[];
    }
  }

  List<int> missingIndexes() {
    final current = manifest;
    if (current == null) return const <int>[];
    return M05FileTransferCore.missingChunkIndexes(
      manifest: current,
      receivedIndexes: _chunks.keys,
    );
  }

  FileTransferReceiverSnapshot snapshot() {
    final current = manifest;
    if (current == null) throw StateError('No manifest to snapshot');
    return FileTransferReceiverSnapshot(
      manifest: current,
      receivedChunks: <int, Uint8List>{
        for (final entry in _chunks.entries)
          entry.key: Uint8List.fromList(entry.value.bytes),
      },
    );
  }
}
