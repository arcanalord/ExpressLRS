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

final class File1TransportBridge {
  File1TransportBridge({
    required Future<void> Function(Uint8List payload) sendBytes,
    required void Function(File1TransportReceived received) onReceived,
    this.tickInterval = const Duration(milliseconds: 25),
  })  : _sendBytes = sendBytes,
        _onReceived = onReceived;

  final Future<void> Function(Uint8List payload) _sendBytes;
  final void Function(File1TransportReceived received) _onReceived;
  final Duration tickInterval;
  final Map<String, _SenderState> _senders = <String, _SenderState>{};
  final Map<String, FileTransferReceiverSession> _receivers =
      <String, FileTransferReceiverSession>{};
  Timer? _timer;
  bool _driving = false;

  Future<void> send(FileTransferPlan plan) {
    final id = plan.manifest.transferId;
    if (_senders.containsKey(id)) {
      return Future<void>.error(StateError('FILE/1 transfer already active: $id'));
    }
    final state = _SenderState(FileTransferSenderSession(plan: plan));
    _senders[id] = state;
    _ensureTimer();
    unawaited(_drive());
    return state.completer.future;
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
      _completeSenderIfTerminal(frame.transferId, senderState);
      return;
    }

    final receiver = _receivers.putIfAbsent(
      frame.transferId,
      FileTransferReceiverSession.new,
    );
    final responses = receiver.onFrame(frame);
    if (receiver.isComplete) {
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
      await _sendBytes(File1Codec.encode(response));
    }
  }

  Future<void> _drive() async {
    if (_driving) return;
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
        for (final frame in outbound) {
          if (frame.type == File1FrameType.manifest) {
            state.lastManifestSentMs = now;
          }
          await _sendBytes(File1Codec.encode(frame));
        }
        _completeSenderIfTerminal(entry.key, state);
      }
    } catch (error, stackTrace) {
      for (final state in _senders.values) {
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

  void _completeSenderIfTerminal(String id, _SenderState state) {
    if (state.session.state == FileTransferSessionState.completed) {
      if (!state.completer.isCompleted) state.completer.complete();
      _senders.remove(id);
    } else if (state.session.state == FileTransferSessionState.failed ||
        state.session.state == FileTransferSessionState.cancelled) {
      if (!state.completer.isCompleted) {
        state.completer.completeError(
          StateError('FILE/1 transfer ended: ${state.session.state.name}'),
        );
      }
      _senders.remove(id);
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(tickInterval, (_) => unawaited(_drive()));
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  void close() {
    _timer?.cancel();
    _timer = null;
    for (final state in _senders.values) {
      if (!state.completer.isCompleted) {
        state.completer.completeError(StateError('FILE/1 bridge closed'));
      }
    }
    _senders.clear();
    _receivers.clear();
  }
}

final class _SenderState {
  _SenderState(this.session);

  final FileTransferSenderSession session;
  final Completer<void> completer = Completer<void>();
  int lastManifestSentMs = -0x7fffffff;
}
