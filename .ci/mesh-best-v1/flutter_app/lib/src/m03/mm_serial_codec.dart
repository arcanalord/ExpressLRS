import 'dart:typed_data';

final class MmSerialBinaryPacket {
  const MmSerialBinaryPacket({required this.tag, required this.payload});

  final int tag;
  final Uint8List payload;
}

/// MM-SERIAL/1 framing for an opaque byte-stream radio.
/// Wire: COBS(binary marker + tag + payload + CRC16-CCITT) + 0x00.
final class MmSerialCodec {
  MmSerialCodec({this.maxFrameBytes = 65535});

  static const List<int> _binaryMarker = <int>[0x1f, 0x4d, 0x42];

  final int maxFrameBytes;
  final List<int> _encoded = <int>[];
  int badFrames = 0;

  Uint8List encodeBinary(Uint8List payload, {required int tag}) {
    if (tag < 0 || tag > 255) {
      throw RangeError.range(tag, 0, 255, 'tag');
    }
    final tagged = Uint8List(_binaryMarker.length + 1 + payload.length)
      ..setRange(0, _binaryMarker.length, _binaryMarker)
      ..[_binaryMarker.length] = tag
      ..setRange(_binaryMarker.length + 1, taggedLength(payload), payload);
    final crc = crc16Ccitt(tagged);
    final withCrc = Uint8List(tagged.length + 2)
      ..setRange(0, tagged.length, tagged)
      ..[tagged.length] = (crc >> 8) & 0xff
      ..[tagged.length + 1] = crc & 0xff;
    return Uint8List.fromList(<int>[...cobsEncode(withCrc), 0]);
  }

  static int taggedLength(Uint8List payload) =>
      _binaryMarker.length + 1 + payload.length;

  List<MmSerialBinaryPacket> feed(Uint8List bytes) {
    final out = <MmSerialBinaryPacket>[];
    for (final byte in bytes) {
      if (byte == 0) {
        if (_encoded.isEmpty) continue;
        final candidate = Uint8List.fromList(_encoded);
        _encoded.clear();
        final decoded = _decode(candidate);
        if (decoded != null) out.add(decoded);
        continue;
      }
      _encoded.add(byte);
      if (_encoded.length > maxFrameBytes) {
        _encoded.clear();
        badFrames++;
      }
    }
    return out;
  }

  void reset() => _encoded.clear();

  MmSerialBinaryPacket? _decode(Uint8List encoded) {
    try {
      final decoded = cobsDecode(encoded);
      if (decoded.length < _binaryMarker.length + 1 + 2) {
        throw const FormatException('MM-SERIAL frame too short');
      }
      final payload = Uint8List.sublistView(decoded, 0, decoded.length - 2);
      final expected =
          (decoded[decoded.length - 2] << 8) | decoded[decoded.length - 1];
      if (crc16Ccitt(payload) != expected) {
        throw const FormatException('MM-SERIAL CRC mismatch');
      }
      for (var i = 0; i < _binaryMarker.length; i++) {
        if (payload[i] != _binaryMarker[i]) {
          throw const FormatException('MM-SERIAL binary marker mismatch');
        }
      }
      return MmSerialBinaryPacket(
        tag: payload[_binaryMarker.length],
        payload: Uint8List.fromList(
          payload.sublist(_binaryMarker.length + 1),
        ),
      );
    } on Object {
      badFrames++;
      return null;
    }
  }

  static int crc16Ccitt(List<int> bytes) {
    var crc = 0xffff;
    for (final byte in bytes) {
      crc ^= (byte & 0xff) << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xffff
            : (crc << 1) & 0xffff;
      }
    }
    return crc;
  }

  static Uint8List cobsEncode(Uint8List input) {
    final out = <int>[0];
    var codeIndex = 0;
    var code = 1;
    for (final byte in input) {
      if (byte == 0) {
        out[codeIndex] = code;
        codeIndex = out.length;
        out.add(0);
        code = 1;
      } else {
        out.add(byte);
        code++;
        if (code == 0xff) {
          out[codeIndex] = code;
          codeIndex = out.length;
          out.add(0);
          code = 1;
        }
      }
    }
    out[codeIndex] = code;
    return Uint8List.fromList(out);
  }

  static Uint8List cobsDecode(Uint8List input) {
    if (input.isEmpty) throw const FormatException('empty COBS frame');
    final out = <int>[];
    var index = 0;
    while (index < input.length) {
      final code = input[index++];
      if (code == 0) throw const FormatException('zero inside COBS frame');
      final end = index + code - 1;
      if (end > input.length) throw const FormatException('truncated COBS');
      while (index < end) {
        out.add(input[index++]);
      }
      if (code != 0xff && index < input.length) out.add(0);
    }
    return Uint8List.fromList(out);
  }
}
