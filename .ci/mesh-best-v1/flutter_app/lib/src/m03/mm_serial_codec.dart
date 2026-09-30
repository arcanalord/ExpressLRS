import 'dart:typed_data';

/// Canonical MM-SERIAL/1 framing shared with MM U1.
///
/// Wire: COBS(payload + CRC16-CCITT big-endian) + 0x00 delimiter.
///
/// This layer owns framing only. It does not add Best-specific marker/tag bytes
/// and does not parse MMRP/application semantics.
final class MmSerialCodec {
  MmSerialCodec({this.maxFrameBytes = 65535});

  final int maxFrameBytes;
  final List<int> _encoded = <int>[];
  int badFrames = 0;
  int cobsErrors = 0;
  int crcErrors = 0;
  int shortFrames = 0;
  int oversizedFrames = 0;

  Uint8List encode(Uint8List payload) {
    final crc = crc16Ccitt(payload);
    final withCrc = Uint8List(payload.length + 2)
      ..setRange(0, payload.length, payload)
      ..[payload.length] = (crc >> 8) & 0xff
      ..[payload.length + 1] = crc & 0xff;
    return Uint8List.fromList(<int>[...cobsEncode(withCrc), 0]);
  }

  List<Uint8List> feed(Uint8List bytes) {
    final out = <Uint8List>[];
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
        oversizedFrames++;
      }
    }
    return out;
  }

  void reset() => _encoded.clear();

  Uint8List? _decode(Uint8List encoded) {
    Uint8List decoded;
    try {
      decoded = cobsDecode(encoded);
    } on FormatException {
      badFrames++;
      cobsErrors++;
      return null;
    }
    if (decoded.length < 3) {
      badFrames++;
      shortFrames++;
      return null;
    }
    final payload = Uint8List.fromList(decoded.sublist(0, decoded.length - 2));
    final expected =
        (decoded[decoded.length - 2] << 8) | decoded[decoded.length - 1];
    if (crc16Ccitt(payload) != expected) {
      badFrames++;
      crcErrors++;
      return null;
    }
    return payload;
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
