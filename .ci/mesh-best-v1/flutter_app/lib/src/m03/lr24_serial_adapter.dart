import 'dart:async';
import 'dart:typed_data';

import '../m12/router.dart';
import 'byte_stream_link.dart';
import 'mm_serial_codec.dart';
import 'transport_adapter.dart';

/// Transparent LR24 M03 adapter over canonical MM-SERIAL/1.
///
/// It deliberately does not add a Best-specific transport envelope on the
/// wire. PreparedTransportPacket.protectedBytes are passed directly as the
/// MM-SERIAL payload, matching MM U1's proven MmSerialPreparedTransport.
///
/// [localBinding]/[peerBinding] are local route metadata for the HIL pair;
/// they are not serialized onto the radio wire.
final class Lr24SerialAdapter implements PreparedTransportAdapter {
  Lr24SerialAdapter({
    required Lr24ByteStreamLink link,
    required this.localBinding,
    this.peerBinding = 'bound:single-peer',
    MmSerialCodec? codec,
  })  : _link = link,
        _codec = codec ?? MmSerialCodec() {
    _subscription = _link.received.listen(_onBytes);
  }

  final Lr24ByteStreamLink _link;
  final String localBinding;
  final String peerBinding;
  final MmSerialCodec _codec;
  final StreamController<TransportInboundFrame> _inbound =
      StreamController<TransportInboundFrame>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  bool Function(Uint8List payload)? _controlHandler;

  @override
  String get id => 'lr24';

  @override
  bool get available => _link.isOpen;

  @override
  Stream<TransportInboundFrame> get inbound => _inbound.stream;

  int get badFrames => _codec.badFrames;

  void setControlHandler(bool Function(Uint8List payload)? handler) {
    _controlHandler = handler;
  }

  Future<void> sendRawPayload(Uint8List payload) async {
    if (!available) throw StateError('lr24-link-closed');
    await _link.write(_codec.encode(Uint8List.fromList(payload)));
  }

  @override
  Future<TransportSubmitResult> submit(PreparedTransportPacket packet) async {
    if (!available) {
      return const TransportSubmitResult(
        TransportSubmitStatus.unavailable,
        detail: 'lr24-link-closed',
      );
    }
    if (packet.transportId != id) {
      return const TransportSubmitResult(
        TransportSubmitStatus.rejected,
        detail: 'lr24-wrong-transport',
      );
    }
    if (packet.transportBinding.trim().isEmpty) {
      return const TransportSubmitResult(
        TransportSubmitStatus.rejected,
        detail: 'lr24-binding-required',
      );
    }

    try {
      await sendRawPayload(packet.protectedBytes);
      return const TransportSubmitResult(TransportSubmitStatus.accepted);
    } on Object catch (error) {
      return TransportSubmitResult(
        TransportSubmitStatus.rejected,
        detail: 'lr24-write-failed:$error',
      );
    }
  }

  void _onBytes(Uint8List bytes) {
    for (final payload in _codec.feed(bytes)) {
      if (_controlHandler?.call(Uint8List.fromList(payload)) == true) {
        continue;
      }
      _inbound.add(
        TransportInboundFrame(
          transportId: id,
          sourceBinding: peerBinding,
          // MM-SERIAL/1 carries only opaque application bytes; it does not
          // carry a transport idempotency token on ingress.
          transportToken: 'mm-serial/1',
          protectedBytes: payload,
        ),
      );
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _codec.reset();
    await _inbound.close();
  }
}
