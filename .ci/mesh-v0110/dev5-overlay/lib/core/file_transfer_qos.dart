import 'dart:collection';

enum M05TrafficClass { control, text, file }

final class M05QueuedFrame<T> {
  const M05QueuedFrame({required this.trafficClass, required this.value});
  final M05TrafficClass trafficClass;
  final T value;
}

final class M05QosScheduler<T> {
  M05QosScheduler({this.maxFileBurst = 4, this.fileStarvationGuard = 16}) {
    if (maxFileBurst <= 0) throw RangeError.value(maxFileBurst, 'maxFileBurst');
    if (fileStarvationGuard <= 0) {
      throw RangeError.value(fileStarvationGuard, 'fileStarvationGuard');
    }
  }

  final int maxFileBurst;
  final int fileStarvationGuard;
  final Queue<T> _control = Queue<T>();
  final Queue<T> _text = Queue<T>();
  final Queue<T> _file = Queue<T>();
  int _consecutiveFile = 0;
  int _highPrioritySinceFile = 0;

  int get pendingControl => _control.length;
  int get pendingText => _text.length;
  int get pendingFile => _file.length;
  bool get isEmpty => _control.isEmpty && _text.isEmpty && _file.isEmpty;

  void enqueue(M05TrafficClass trafficClass, T value) {
    switch (trafficClass) {
      case M05TrafficClass.control:
        _control.add(value);
      case M05TrafficClass.text:
        _text.add(value);
      case M05TrafficClass.file:
        _file.add(value);
    }
  }

  M05QueuedFrame<T>? takeNext() {
    if (isEmpty) return null;

    final fileWaiting = _file.isNotEmpty;
    final forceFile =
        fileWaiting && _highPrioritySinceFile >= fileStarvationGuard;
    if (forceFile) return _takeFile();

    if (_control.isNotEmpty)
      return _takeHigh(M05TrafficClass.control, _control);
    if (_text.isNotEmpty) return _takeHigh(M05TrafficClass.text, _text);

    if (_file.isNotEmpty) return _takeFile();
    return null;
  }

  List<M05QueuedFrame<T>> drain({required int budget}) {
    if (budget < 0) throw RangeError.value(budget, 'budget');
    final out = <M05QueuedFrame<T>>[];
    while (out.length < budget) {
      final next = takeNext();
      if (next == null) break;
      out.add(next);
    }
    return out;
  }

  M05QueuedFrame<T> _takeHigh(M05TrafficClass kind, Queue<T> queue) {
    _consecutiveFile = 0;
    if (_file.isNotEmpty) _highPrioritySinceFile++;
    return M05QueuedFrame<T>(trafficClass: kind, value: queue.removeFirst());
  }

  M05QueuedFrame<T> _takeFile() {
    if (_consecutiveFile >= maxFileBurst &&
        (_control.isNotEmpty || _text.isNotEmpty)) {
      if (_control.isNotEmpty)
        return _takeHigh(M05TrafficClass.control, _control);
      return _takeHigh(M05TrafficClass.text, _text);
    }
    _consecutiveFile++;
    _highPrioritySinceFile = 0;
    return M05QueuedFrame<T>(
      trafficClass: M05TrafficClass.file,
      value: _file.removeFirst(),
    );
  }
}
