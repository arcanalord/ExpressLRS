import 'dart:convert';
import 'dart:typed_data';

abstract final class MmUart1FrameType {
  static const int hello = 0x01;
  static const int getInfo = 0x02;
  static const int getCaps = 0x03;
  static const int getState = 0x04;
  static const int getStats = 0x05;
  static const int radioInit = 0x10;
  static const int setProfile = 0x11;
  static const int send = 0x12;
  static const int cancel = 0x13;
  static const int resetStats = 0x14;
  static const int reboot = 0x15;
  static const int ready = 0x80;
  static const int stateChanged = 0x81;
  static const int rxPacket = 0x82;
  static const int txAccepted = 0x83;
  static const int txResult = 0x84;
  static const int linkStats = 0x85;
  static const int radioError = 0x86;
  static const int deviceReset = 0x87;
  static const int response = 0x90;
}

final class MmUart1Frame {
  const MmUart1Frame({required this.version, required this.type, required this.sequence, required this.payloadBytes});
  final int version;
  final int type;
  final int sequence;
  final Uint8List payloadBytes;
  Object? jsonPayload() => payloadBytes.isEmpty ? null : jsonDecode(utf8.decode(payloadBytes));
}

abstract final class MmUart1Codec {
  static const int version = 1;

  static int crc16Ccitt(Iterable<int> bytes, {int initial = 0xffff}) {
    var crc = initial & 0xffff;
    for (final raw in bytes) {
      crc ^= (raw & 0xff) << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? (((crc << 1) ^ 0x1021) & 0xffff) : ((crc << 1) & 0xffff);
      }
    }
    return crc & 0xffff;
  }

  static Uint8List cobsEncode(Iterable<int> input) {
    final src = Uint8List.fromList(input.map((e) => e & 0xff).toList());
    final out = Uint8List(src.length + (src.length / 254).ceil() + 1);
    var read = 0, write = 1, codeIndex = 0, code = 1;
    while (read < src.length) {
      if (src[read] == 0) {
        out[codeIndex] = code; code = 1; codeIndex = write++; read++;
      } else {
        out[write++] = src[read++]; code++;
        if (code == 0xff) { out[codeIndex] = code; code = 1; codeIndex = write++; }
      }
    }
    out[codeIndex] = code;
    return Uint8List.sublistView(out, 0, write);
  }

  static Uint8List cobsDecode(Iterable<int> input) {
    final src = Uint8List.fromList(input.map((e) => e & 0xff).toList());
    final out = Uint8List(src.length);
    var read = 0, write = 0;
    while (read < src.length) {
      final code = src[read++];
      if (code == 0) throw const FormatException('COBS_ZERO_CODE');
      final copyCount = code - 1;
      if (read + copyCount > src.length) throw const FormatException('COBS_TRUNCATED');
      for (var i = 0; i < copyCount; i++) out[write++] = src[read++];
      if (code != 0xff && read < src.length) out[write++] = 0;
    }
    return Uint8List.sublistView(out, 0, write);
  }

  static Uint8List encodeFrame({required int type, int sequence = 0, Object? payload, int frameVersion = version}) {
    final body = switch (payload) {
      null => Uint8List(0),
      Uint8List v => v,
      List<int> v => Uint8List.fromList(v),
      String v => Uint8List.fromList(utf8.encode(v)),
      _ => Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    };
    if (body.length > 0xffff) throw const FormatException('PAYLOAD_TOO_LARGE');
    final raw = Uint8List(6 + body.length + 2);
    raw[0] = frameVersion & 0xff; raw[1] = type & 0xff;
    raw[2] = sequence & 0xff; raw[3] = (sequence >> 8) & 0xff;
    raw[4] = body.length & 0xff; raw[5] = (body.length >> 8) & 0xff;
    raw.setRange(6, 6 + body.length, body);
    final crc = crc16Ccitt(Uint8List.sublistView(raw, 0, raw.length - 2));
    raw[raw.length - 2] = crc & 0xff; raw[raw.length - 1] = (crc >> 8) & 0xff;
    return Uint8List.fromList([...cobsEncode(raw), 0]);
  }

  static MmUart1Frame decodeFrame(Iterable<int> encodedWithoutDelimiter) {
    final raw = cobsDecode(encodedWithoutDelimiter);
    if (raw.length < 8) throw const FormatException('FRAME_TOO_SHORT');
    if (raw[0] != version) throw const FormatException('UNSUPPORTED_VERSION');
    final payloadLength = raw[4] | (raw[5] << 8);
    if (raw.length != 6 + payloadLength + 2) throw const FormatException('BAD_LENGTH');
    final expected = raw[raw.length - 2] | (raw[raw.length - 1] << 8);
    final actual = crc16Ccitt(Uint8List.sublistView(raw, 0, raw.length - 2));
    if (expected != actual) throw const FormatException('BAD_CRC');
    return MmUart1Frame(
      version: raw[0], type: raw[1], sequence: raw[2] | (raw[3] << 8),
      payloadBytes: Uint8List.sublistView(raw, 6, 6 + payloadLength),
    );
  }
}
