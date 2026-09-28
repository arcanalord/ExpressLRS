import 'dart:async';

import '../core/file_transfer_qos.dart';

final class M05TransportQosAdapter {
  M05TransportQosAdapter({
    required Future<void> Function(Map<String, Object?> frame) writeRaw,
    int maxFileBurst = 4,
    int fileStarvationGuard = 16,
  })  : _writeRaw = writeRaw,
        _scheduler = M05QosScheduler<_PendingOutbound>(
          maxFileBurst: maxFileBurst,
          fileStarvationGuard: fileStarvationGuard,
        );

  final Future<void> Function(Map<String, Object?> frame) _writeRaw;
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
          await _writeRaw(pending.frame);
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
  _PendingOutbound(this.frame);

  final Map<String, Object?> frame;
  final Completer<void> completer = Completer<void>();
}
