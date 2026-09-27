import 'dart:convert';
import 'dart:typed_data';

/// MM-SERIAL/1 P0 framing for transparent byte-stream radios.
///
/// Wire format:
///   COBS(JSON UTF-8 + CRC16-CCITT big-endian) + 0x00
///
/// The JSON object carries the existing MMRP/1 logical envelope. This layer
/// owns stream framing only; delivery, retries and recipient ACK stay in M02.
final class MmSerialCodec {
  MmSerialCodec({this.maxFrameBytes = 65535});

  final int maxFrameBytes;
  final List<int> _encoded = <int>[];
  int badFrames = 0;

  Uint8List encode(Map<String, Object?> frame) {
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(frame)));
    final crc = crc16Ccitt(payload);
    final withCrc = Uint8List(payload.length + 2)
      ..setRange(0, payload.length, payload)
      ..[payload.length] = (crc >> 8) & 0xff
      ..[payload.length + 1] = crc & 0xff;
    final encoded = cobsEncode(withCrc);
    return Uint8List.fromList(<int>[...encoded, 0]);
  }

  List<Map<String, dynamic>> feed(Uint8List bytes) {
    final out = <Map<String, dynamic>>[];
    for (final byte in bytes) {
      if (byte == 0) {
        if (_encoded.isEmpty) continue;
        final candidate = Uint8List.fromList(_encoded);
        _encoded.clear();
        final decoded = _decodeFrame(candidate);
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

  Map<String, dynamic>? _decodeFrame(Uint8List encoded) {
    try {
      final decoded = cobsDecode(encoded);
      if (decoded.length < 3) throw const FormatException('frame too short');
      final payload = Uint8List.sublistView(decoded, 0, decoded.length - 2);
      final expected =
          (decoded[decoded.length - 2] << 8) | decoded[decoded.length - 1];
      if (crc16Ccitt(payload) != expected) {
        throw const FormatException('CRC mismatch');
      }
      final value = jsonDecode(utf8.decode(payload));
      if (value is! Map) throw const FormatException('frame is not an object');
      return Map<String, dynamic>.from(value);
    } catch (_) {
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
      final code = input[index];
      if (code == 0) throw const FormatException('zero inside COBS frame');
      index++;
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
