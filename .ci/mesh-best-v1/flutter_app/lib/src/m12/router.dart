import 'dart:typed_data';

import '../m07/protector.dart';

final class PreparedTransportPacket {
  PreparedTransportPacket({
    required this.routeAttemptId,
    required this.transportId,
    required Uint8List protectedBytes,
    required this.idempotencyToken,
  }) : _protectedBytes = Uint8List.fromList(protectedBytes);

  final String routeAttemptId;
  final String transportId;
  final Uint8List _protectedBytes;
  Uint8List get protectedBytes => Uint8List.fromList(_protectedBytes);
  final String idempotencyToken;
}

abstract interface class SingleRouteRouter {
  PreparedTransportPacket prepare(ProtectedEnvelope envelope);
}

final class Lr24SingleRouteRouter implements SingleRouteRouter {
  const Lr24SingleRouteRouter();

  @override
  PreparedTransportPacket prepare(ProtectedEnvelope envelope) {
    return PreparedTransportPacket(
      routeAttemptId: 'lr24:${envelope.messageId}',
      transportId: 'lr24',
      protectedBytes: envelope.protectedBytes,
      idempotencyToken: envelope.messageId,
    );
  }
}
