enum SourceEventType { data, heartbeat, reconnect, error, disconnect }

final class SourceEventV1<T> {
  final SourceEventType type;
  final DateTime timestamp;
  final T? data;
  final String? reason;

  const SourceEventV1({
    required this.type,
    required this.timestamp,
    this.data,
    this.reason,
  });
}

abstract interface class SourceAdapterV1<T> {
  String get sourceId;
  bool get isConnected;
  Stream<SourceEventV1<T>> get events;
  Future<void> start();
  Future<void> stop();
}
