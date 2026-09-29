import '../m12/router.dart';

enum TransportSubmitStatus { accepted, unavailable, rejected }

final class TransportSubmitResult {
  const TransportSubmitResult(this.status, {this.detail});

  final TransportSubmitStatus status;
  final String? detail;
}

abstract interface class PreparedTransportAdapter {
  String get id;
  bool get available;
  Future<TransportSubmitResult> submit(PreparedTransportPacket packet);
}

final class MemoryLr24Adapter implements PreparedTransportAdapter {
  MemoryLr24Adapter({this.available = true});

  @override
  final bool available;

  @override
  String get id => 'lr24';

  final List<PreparedTransportPacket> submitted =
      <PreparedTransportPacket>[];

  @override
  Future<TransportSubmitResult> submit(PreparedTransportPacket packet) async {
    if (!available) {
      return const TransportSubmitResult(
        TransportSubmitStatus.unavailable,
        detail: 'lr24-unavailable',
      );
    }
    submitted.add(packet);
    return const TransportSubmitResult(TransportSubmitStatus.accepted);
  }
}
