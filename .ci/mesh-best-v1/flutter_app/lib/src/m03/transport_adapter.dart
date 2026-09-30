import 'dart:async';
import 'dart:typed_data';

import '../m12/router.dart';

enum TransportSubmitStatus { accepted, unavailable, rejected }

final class TransportInboundFrame {
  TransportInboundFrame({
    required this.transportId,
    required this.sourceBinding,
    required this.transportToken,
    required Uint8List protectedBytes,
  }) : _protectedBytes = Uint8List.fromList(protectedBytes);

  final String transportId;
  final String sourceBinding;
  final String transportToken;
  final Uint8List _protectedBytes;
  Uint8List get protectedBytes => Uint8List.fromList(_protectedBytes);
}

final class TransportSubmitResult {
  const TransportSubmitResult(this.status, {this.detail});

  final TransportSubmitStatus status;
  final String? detail;
}

abstract interface class PreparedTransportAdapter {
  String get id;
  bool get available;
  Stream<TransportInboundFrame> get inbound;
  Future<TransportSubmitResult> submit(PreparedTransportPacket packet);
}

final class MemoryLr24Adapter implements PreparedTransportAdapter {
  MemoryLr24Adapter({this.available = true});

  @override
  final bool available;

  @override
  String get id => 'lr24';

  @override
  Stream<TransportInboundFrame> get inbound =>
      const Stream<TransportInboundFrame>.empty();

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
