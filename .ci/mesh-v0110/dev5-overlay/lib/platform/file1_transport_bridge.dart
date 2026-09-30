import 'dart:async';
import 'dart:typed_data';

import '../core/file_transfer_core.dart';
import '../core/file_transfer_protocol.dart';
import '../core/file_transfer_session.dart';

final class File1TransportReceived {
  const File1TransportReceived({
    required this.manifest,
    required this.bytes,
  });

  final FileTransferManifest manifest;
  final Uint8List bytes;
}

final class File1TransportProgress {
  const File1TransportProgress({
    required this.transferId,
    required this.state,
    required this.ackedChunks,
    required this.totalChunks,
    this.failureReason,
  });

  final String transferId;
  final FileTransferSessionState state;
  final int ackedChunks;
  final int totalChunks;
  final String? failureReason;

  double get fraction =>
      totalChunks == 0 ? 1 : ackedChunks / totalChunks;
}

final class File1TransportBridge {
  File1TransportBridge({
    required Future<void> Function(Uint8List payload) sendBytes,
    required void Function(File1TransportReceived received) onReceived,
    void Function(File1TransportProgress progress)? onProgress,
    this.tickInterval = const Duration(milliseconds: 25),
  })  : _sendBytes = sendBytes,
        _onReceived = onReceived,
        _onProgress = onProgress;

  final Future<void> Function(Uint8List payload) _sendBytes;
  final void Function(File1TransportReceived received) _onReceived;
  final void Function(File1TransportProgress progress)? _onProgress;
  final Duration tickInterval;
  final Map<String, _SenderState> _senders = <String, _SenderState>{};
  final Map<String, FileTransferReceiverSession> _receivers =
      <String, FileTransferReceiverSession>{};
  final Map<String, int> _completedReceiverAtMs = <String, int>{};
  static const int _completedReceiverRetentionMs = 5 * 60 * 1000;
  static const int _maxCompletedReceiverIds = 64;
  Timer? _timer;
  bool _driving = false;
  bool _linkAvailable = true;

  bool get hasActiveSenders => _senders.isNotEmpty;

  void pauseForLinkLoss() {
    if (!_linkAvailable) return;
    _linkAvailable = false;
    for (final entry in _senders.entries) {
      entry.value.session.pauseForLinkLoss();
      _emitProgress(entry.key, entry.value, force: true);
    }
  }

  void resumeAfterLink() {
    _linkAvailable = true;
    for (final entry in _senders.entries) {
      entry.value.session.resumeAfterLink();
      entry.value.lastManifestSentMs = -0x7fffffff;
      entry.value.consecutiveWriteFailures = 0;
      entry.value.lastWriteError = null;
      _emitProgress(entry.key, entry.value, force: true);
    }
    if (_senders.isNotEmpty) {
      _ensureTimer();
      unawaited(_drive());
    }
  }

  Future<void> send(FileTransferPlan plan) {
    final id = plan.manifest.transferId;
    if (_senders.containsKey(id)) {
      return Future<void>.error(
        StateError('FILE/1 transfer already active: $id'),
      );
    }
    if (!_linkAvailable) {
      return Future<void>.error(StateError('FILE/1 link unavailable'));
    }
    final state = _SenderState(FileTransferSenderSession(plan: plan));
    _senders[id] = state;
    _emitProgress(id, state, force: true);
    _ensureTimer();
    unawaited(_drive());
    return state.completer.future;
  }

  Future<bool> cancel(String transferId) async {
    final state = _senders[transferId];
    if (state == null || state.session.isTerminal) return false;
    state.session.cancel();
    _emitProgress(transferId, state, force: true);
    try {
      await _sendBytes(
        File1Codec.encode(File1Codec.error(transferId, 'cancelled')),
      );
    } catch (_) {
      // Local cancellation must still release the sender even if the link
      // vanished before the remote cancellation notice could be delivered.
    }
    _completeSenderIfTerminal(transferId, state);
    return true;
  }

  Future<void> handleIncoming(Uint8List bytes) async {
    final frame = File1Codec.decode(bytes);
    final senderState = _senders[frame.transferId];
    if (senderState != null &&
        (frame.type == File1FrameType.ack ||
            frame.type == File1FrameType.missing ||
            frame.type == File1FrameType.complete ||
            frame.type == File1FrameType.error)) {
      senderState.session.onFrame(frame, _nowMs());
      _emitProgress(frame.transferId, senderState);
      _completeSenderIfTerminal(frame.transferId, senderState);
      return;
    }

    final now = _nowMs();
    _pruneCompletedReceivers(now);
    if (frame.type == File1FrameType.manifest) {
      _completedReceiverAtMs.remove(frame.transferId);
    } else if (frame.type == File1FrameType.complete &&
        _completedReceiverAtMs.containsKey(frame.transferId)) {
      try {
        await _sendBytes(
          File1Codec.encode(File1Codec.complete(frame.transferId)),
        );
      } catch (_) {
        // Sender retries COMPLETE; keep the tombstone for idempotent recovery.
      }
      return;
    }

    if (frame.type == File1FrameType.error) {
      _receivers.remove(frame.transferId);
      return;
    }

    final receiver = _receivers.putIfAbsent(
      frame.transferId,
      FileTransferReceiverSession.new,
    );
    final responses = receiver.onFrame(frame);
    if (receiver.isComplete) {
      _rememberCompletedReceiver(frame.transferId, now);
      final manifest = receiver.manifest;
      final payload = receiver.completedBytes;
      if (manifest != null && payload != null) {
        _onReceived(
          File1TransportReceived(
            manifest: manifest,
            bytes: Uint8List.fromList(payload),
          ),
        );
      }
      _receivers.remove(frame.transferId);
    }
    for (final response in responses) {
      try {
        await _sendBytes(File1Codec.encode(response));
      } catch (_) {
        // ACK/COMPLETE are idempotent; the sender retries the request.
      }
    }
  }

  Future<void> _drive() async {
    if (_driving || !_linkAvailable) return;
    _driving = true;
    try {
      final now = _nowMs();
      for (final entry in _senders.entries.toList(growable: false)) {
        final state = entry.value;
        if (state.session.state == FileTransferSessionState.sendingManifest &&
            now - state.lastManifestSentMs < state.session.ackTimeoutMs) {
          continue;
        }
        final outbound = state.session.poll(now);
        _emitProgress(entry.key, state);
        for (final frame in outbound) {
          if (frame.type == File1FrameType.manifest) {
            state.lastManifestSentMs = now;
          }
          try {
            await _sendBytes(File1Codec.encode(frame));
            state.consecutiveWriteFailures = 0;
            state.lastWriteError = null;
          } catch (error) {
            // A single UART write exception can be transient (including the
            // final COMPLETE control frame). Keep the FILE/1 session alive and
            // let its timeout/retry state machine resend the same logical
            // frame. Real USB detach/error is signalled separately by M03 and
            // calls pauseForLinkLoss(), which freezes retry timers.
            state.consecutiveWriteFailures++;
            state.lastWriteError = error;
            break;
          }
        }
        _completeSenderIfTerminal(entry.key, state);
      }
    } catch (error, stackTrace) {
      for (final entry in _senders.entries.toList(growable: false)) {
        final state = entry.value;
        state.session.state = FileTransferSessionState.failed;
        _emitProgress(entry.key, state, force: true);
        if (!state.completer.isCompleted) {
          state.completer.completeError(error, stackTrace);
        }
      }
      _senders.clear();
    } finally {
      _driving = false;
      if (_senders.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  void _emitProgress(
    String id,
    _SenderState state, {
    bool force = false,
  }) {
    final callback = _onProgress;
    if (callback == null) return;
    final session = state.session;
    if (!force &&
        state.lastState == session.state &&
        state.lastAckedChunks == session.ackedChunkCount) {
      return;
    }
    state.lastState = session.state;
    state.lastAckedChunks = session.ackedChunkCount;
    callback(
      File1TransportProgress(
        transferId: id,
        state: session.state,
        ackedChunks: session.ackedChunkCount,
        totalChunks: session.totalChunkCount,
        failureReason: session.failureReason,
      ),
    );
  }

  void _completeSenderIfTerminal(String id, _SenderState state) {
    if (state.session.state == FileTransferSessionState.completed) {
      _emitProgress(id, state, force: true);
      if (!state.completer.isCompleted) state.completer.complete();
      _senders.remove(id);
    } else if (state.session.state == FileTransferSessionState.failed ||
        state.session.state == FileTransferSessionState.cancelled) {
      _emitProgress(id, state, force: true);
      if (!state.completer.isCompleted) {
        state.completer.completeError(
          StateError(
            'FILE/1 transfer ended: ${state.session.state.name}' +
                (state.session.failureReason == null
                    ? ''
                    : ' (${state.session.failureReason})'),
          ),
        );
      }
      _senders.remove(id);
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(tickInterval, (_) => unawaited(_drive()));
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  void _rememberCompletedReceiver(String transferId, int nowMs) {
    _completedReceiverAtMs[transferId] = nowMs;
    _pruneCompletedReceivers(nowMs);
    while (_completedReceiverAtMs.length > _maxCompletedReceiverIds) {
      _completedReceiverAtMs.remove(_completedReceiverAtMs.keys.first);
    }
  }

  void _pruneCompletedReceivers(int nowMs) {
    _completedReceiverAtMs.removeWhere(
      (_, completedAtMs) =>
          nowMs - completedAtMs > _completedReceiverRetentionMs,
    );
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    for (final entry in _senders.entries) {
      final state = entry.value;
      state.session.state = FileTransferSessionState.failed;
      _emitProgress(entry.key, state, force: true);
      if (!state.completer.isCompleted) {
        state.completer.completeError(StateError('FILE/1 bridge closed'));
      }
    }
    _senders.clear();
    _receivers.clear();
    _completedReceiverAtMs.clear();
  }
}

final class _SenderState {
  _SenderState(this.session);

  final FileTransferSenderSession session;
  final Completer<void> completer = Completer<void>();
  int lastManifestSentMs = -0x7fffffff;
  FileTransferSessionState? lastState;
  int lastAckedChunks = -1;
  int consecutiveWriteFailures = 0;
  Object? lastWriteError;
}
