import 'dart:async';
import 'dart:typed_data';

import '../core/file_transfer_qos.dart';

final class M05TransportQosAdapter {
  M05TransportQosAdapter({
    required Future<void> Function(Map<String, Object?> frame) writeRaw,
    required Future<void> Function(Uint8List payload) writeRawFile1,
    int maxFileBurst = 4,
    int fileStarvationGuard = 16,
  })  : _writeRaw = writeRaw,
        _writeRawFile1 = writeRawFile1,
        _scheduler = M05QosScheduler<_PendingOutbound>(
          maxFileBurst: maxFileBurst,
          fileStarvationGuard: fileStarvationGuard,
        );

  final Future<void> Function(Map<String, Object?> frame) _writeRaw;
  final Future<void> Function(Uint8List payload) _writeRawFile1;
  final M05QosScheduler<_PendingOutbound> _scheduler;
  bool _pumping = false;

  int get pendingControl => _scheduler.pendingControl;
  int get pendingText => _scheduler.pendingText;
  int get pendingFile => _scheduler.pendingFile;
  bool get isIdle => !_pumping && _scheduler.isEmpty;

  Future<void> send(Map<String, Object?> frame) {
    final pending = _PendingOutbound(Map<String, Object?>.unmodifiable(frame));
    _scheduler.enqueue(classify(frame), pending);
    _ensurePump();
    return pending.completer.future;
  }

  Future<void> sendFile1(Uint8List payload) {
    final pending = _PendingOutbound.file1(Uint8List.fromList(payload));
    _scheduler.enqueue(M05TrafficClass.file, pending);
    _ensurePump();
    return pending.completer.future;
  }

  M05TrafficClass classify(Map<String, Object?> frame) {
    final protocol = frame['p']?.toString();
    final kind = frame['k']?.toString();
    final messageClass = frame['class']?.toString();

    if (protocol == 'FILE/1') return M05TrafficClass.file;

    switch (kind) {
      case 'data':
      case 'channel_data':
      case 'group_data':
        if (messageClass == 'text') return M05TrafficClass.text;
        return M05TrafficClass.control;
      case 'ack':
      case 'channel_receipt':
      case 'group_receipt':
      case 'hello':
      case 'group_descriptor':
      case 'ping':
      case 'pong':
        return M05TrafficClass.control;
      default:
        return M05TrafficClass.control;
    }
  }

  void _ensurePump() {
    if (_pumping) return;
    _pumping = true;
    scheduleMicrotask(_pump);
  }

  Future<void> _pump() async {
    try {
      while (true) {
        final next = _scheduler.takeNext();
        if (next == null) break;
        final pending = next.value;
        try {
          if (pending.file1Payload != null) {
            await _writeRawFile1(pending.file1Payload!);
          } else {
            await _writeRaw(pending.frame!);
          }
          if (!pending.completer.isCompleted) pending.completer.complete();
        } catch (error, stackTrace) {
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(error, stackTrace);
          }
        }
      }
    } finally {
      _pumping = false;
      if (!_scheduler.isEmpty) _ensurePump();
    }
  }
}

final class _PendingOutbound {
  _PendingOutbound(Map<String, Object?> frame)
      : frame = frame,
        file1Payload = null;

  _PendingOutbound.file1(Uint8List payload)
      : frame = null,
        file1Payload = payload;

  final Map<String, Object?>? frame;
  final Uint8List? file1Payload;
  final Completer<void> completer = Completer<void>();
}
