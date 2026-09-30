import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../m12/router.dart';
import 'byte_stream_link.dart';
import 'mm_serial_codec.dart';
import 'transport_adapter.dart';

final class Lr24SerialAdapter implements PreparedTransportAdapter {
  Lr24SerialAdapter({
    required Lr24ByteStreamLink link,
    required this.localBinding,
    MmSerialCodec? codec,
  })  : _link = link,
        _codec = codec ?? MmSerialCodec() {
    _subscription = _link.received.listen(_onBytes);
  }

  static const int _preparedPacketTag = 2;

  final Lr24ByteStreamLink _link;
  final String localBinding;
  final MmSerialCodec _codec;
  final StreamController<TransportInboundFrame> _inbound =
      StreamController<TransportInboundFrame>.broadcast();
  StreamSubscription<Uint8List>? _subscription;

  @override
  String get id => 'lr24';

  @override
  bool get available => _link.isOpen;

  @override
  Stream<TransportInboundFrame> get inbound => _inbound.stream;

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

    final frame = _Lr24PreparedWireFrame(
      sourceBinding: localBinding,
      destinationBinding: packet.transportBinding,
      transportToken: packet.idempotencyToken,
      payload: packet.protectedBytes,
    );
    try {
      await _link.write(
        _codec.encodeBinary(
          frame.encode(),
          tag: _preparedPacketTag,
        ),
      );
      return const TransportSubmitResult(TransportSubmitStatus.accepted);
    } on Object catch (error) {
      return TransportSubmitResult(
        TransportSubmitStatus.rejected,
        detail: 'lr24-write-failed:$error',
      );
    }
  }

  void _onBytes(Uint8List bytes) {
    for (final packet in _codec.feed(bytes)) {
      if (packet.tag != _preparedPacketTag) continue;
      _Lr24PreparedWireFrame frame;
      try {
        frame = _Lr24PreparedWireFrame.decode(packet.payload);
      } on FormatException {
        continue;
      }
      if (frame.destinationBinding != localBinding &&
          frame.destinationBinding != '*') {
        continue;
      }
      _inbound.add(
        TransportInboundFrame(
          transportId: id,
          sourceBinding: frame.sourceBinding,
          transportToken: frame.transportToken,
          protectedBytes: frame.payload,
        ),
      );
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _inbound.close();
  }
}

final class _Lr24PreparedWireFrame {
  _Lr24PreparedWireFrame({
    required this.sourceBinding,
    required this.destinationBinding,
    required this.transportToken,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);

  static const List<int> _magic = <int>[0x4d, 0x4c, 0x31]; // ML1
  static const int _version = 1;

  final String sourceBinding;
  final String destinationBinding;
  final String transportToken;
  final Uint8List payload;

  Uint8List encode() {
    final source = utf8.encode(sourceBinding);
    final destination = utf8.encode(destinationBinding);
    final token = utf8.encode(transportToken);
    if (source.isEmpty || source.length > 255) {
      throw const FormatException('LR24 source binding length');
    }
    if (destination.isEmpty || destination.length > 255) {
      throw const FormatException('LR24 destination binding length');
    }
    if (token.isEmpty || token.length > 255) {
      throw const FormatException('LR24 transport token length');
    }
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..addByte(source.length)
      ..addByte(destination.length)
      ..addByte(token.length)
      ..add(_u32(payload.length))
      ..add(source)
      ..add(destination)
      ..add(token)
      ..add(payload);
    return out.takeBytes();
  }

  static _Lr24PreparedWireFrame decode(Uint8List bytes) {
    const headerLength = 11;
    if (bytes.length < headerLength) {
      throw const FormatException('LR24 prepared frame too short');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('LR24 prepared frame magic');
      }
    }
    if (bytes[3] != _version) {
      throw const FormatException('LR24 prepared frame version');
    }
    final sourceLength = bytes[4];
    final destinationLength = bytes[5];
    final tokenLength = bytes[6];
    final payloadLength = _readU32(bytes, 7);
    final expected =
        headerLength + sourceLength + destinationLength + tokenLength +
            payloadLength;
    if (bytes.length != expected) {
      throw const FormatException('LR24 prepared frame length');
    }
    var offset = headerLength;
    final source = utf8.decode(bytes.sublist(offset, offset + sourceLength));
    offset += sourceLength;
    final destination =
        utf8.decode(bytes.sublist(offset, offset + destinationLength));
    offset += destinationLength;
    final token = utf8.decode(bytes.sublist(offset, offset + tokenLength));
    offset += tokenLength;
    return _Lr24PreparedWireFrame(
      sourceBinding: source,
      destinationBinding: destination,
      transportToken: token,
      payload: Uint8List.fromList(bytes.sublist(offset)),
    );
  }

  static List<int> _u32(int value) => <int>[
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  static int _readU32(List<int> bytes, int offset) =>
      ((bytes[offset] << 24) |
              (bytes[offset + 1] << 16) |
              (bytes[offset + 2] << 8) |
              bytes[offset + 3]) &
          0xffffffff;
}
