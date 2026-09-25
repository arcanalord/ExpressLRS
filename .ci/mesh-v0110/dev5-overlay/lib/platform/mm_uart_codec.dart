import 'dart:convert';
import 'dart:typed_data';

const int mmUartVersion = 1;

abstract final class MmUartFrameType {
  static const int hello = 0x01;
  static const int getInfo = 0x02;
  static const int getCaps = 0x03;
  static const int getState = 0x04;
  static const int getStats = 0x05;
  // Added by the current M03 v0.4.1-dev compatibility contract.
  static const int compatSelftest = 0x06;

  static const int radioInit = 0x10;
  static const int setProfile = 0x11;
  static const int send = 0x12;
  static const int cancel = 0x13;
  static const int resetStats = 0x14;
  static const int reboot = 0x15;
  static const int enterOta = 0x16;
  static const int exitOta = 0x17;

  static const int ready = 0x80;
  static const int stateChanged = 0x81;
  static const int rxPacket = 0x82;
  static const int txAccepted = 0x83;
  static const int txResult = 0x84;
  static const int linkStats = 0x85;
  static const int radioError = 0x86;
  static const int deviceReset = 0x87;
  static const int response = 0x90;

  static const Map<int, String> names = {
    hello: 'HELLO',
    getInfo: 'GET_INFO',
    getCaps: 'GET_CAPS',
    getState: 'GET_STATE',
    getStats: 'GET_STATS',
    compatSelftest: 'COMPAT_SELFTEST',
    radioInit: 'RADIO_INIT',
    setProfile: 'SET_PROFILE',
    send: 'SEND',
    cancel: 'CANCEL',
    resetStats: 'RESET_STATS',
    reboot: 'REBOOT',
    enterOta: 'ENTER_OTA',
    exitOta: 'EXIT_OTA',
    ready: 'READY',
    stateChanged: 'STATE_CHANGED',
    rxPacket: 'RX_PACKET',
    txAccepted: 'TX_ACCEPTED',
    txResult: 'TX_RESULT',
    linkStats: 'LINK_STATS',
    radioError: 'RADIO_ERROR',
    deviceReset: 'DEVICE_RESET',
    response: 'RESPONSE',
  };
}

final class MmUartFrame {
  const MmUartFrame({
    required this.version,
    required this.type,
    required this.sequence,
    required this.payloadBytes,
  });

  final int version;
  final int type;
  final int sequence;
  final Uint8List payloadBytes;

  String get typeName => MmUartFrameType.names[type] ?? 'UNKNOWN';

  Object? decodeJsonPayload() {
    if (payloadBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(payloadBytes));
    } catch (_) {
      throw const FormatException('BAD_JSON_PAYLOAD');
    }
  }
}

int mmUartCrc16Ccitt(Iterable<int> bytes, {int initial = 0xffff}) {
  var crc = initial & 0xffff;
  for (final value in bytes) {
    crc ^= (value & 0xff) << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xffff
          : (crc << 1) & 0xffff;
    }
  }
  return crc & 0xffff;
}

Uint8List mmUartCobsEncode(Iterable<int> input) {
  final source = Uint8List.fromList(input.toList(growable: false));
  final out = Uint8List(source.length + (source.length / 254).ceil() + 1);
  var read = 0;
  var write = 1;
  var codeIndex = 0;
  var code = 1;

  while (read < source.length) {
    if (source[read] == 0) {
      out[codeIndex] = code;
      code = 1;
      codeIndex = write++;
      read++;
    } else {
      out[write++] = source[read++];
      code++;
      if (code == 0xff) {
        out[codeIndex] = code;
        code = 1;
        codeIndex = write++;
      }
    }
  }
  out[codeIndex] = code;
  return Uint8List.sublistView(out, 0, write);
}

Uint8List mmUartCobsDecode(Iterable<int> input) {
  final source = Uint8List.fromList(input.toList(growable: false));
  final out = Uint8List(source.length);
  var read = 0;
  var write = 0;

  while (read < source.length) {
    final code = source[read++];
    if (code == 0) throw const FormatException('COBS_ZERO_CODE');
    final copyCount = code - 1;
    if (read + copyCount > source.length) {
      throw const FormatException('COBS_TRUNCATED');
    }
    for (var i = 0; i < copyCount; i++) {
      out[write++] = source[read++];
    }
    if (code != 0xff && read < source.length) out[write++] = 0;
  }
  return Uint8List.sublistView(out, 0, write);
}

Uint8List _normalizeMmUartPayload(Object? payload) {
  if (payload == null) return Uint8List(0);
  if (payload is Uint8List) return payload;
  if (payload is List<int>) return Uint8List.fromList(payload);
  if (payload is String) return Uint8List.fromList(utf8.encode(payload));
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
}

Uint8List mmUartEncodeFrame({
  required int type,
  int sequence = 0,
  Object? payload,
  int version = mmUartVersion,
}) {
  if (type < 0 || type > 0xff) throw RangeError.range(type, 0, 0xff, 'type');
  if (sequence < 0 || sequence > 0xffff) {
    throw RangeError.range(sequence, 0, 0xffff, 'sequence');
  }
  final body = _normalizeMmUartPayload(payload);
  if (body.length > 0xffff) throw const FormatException('PAYLOAD_TOO_LARGE');

  final raw = Uint8List(6 + body.length + 2);
  raw[0] = version & 0xff;
  raw[1] = type & 0xff;
  raw[2] = sequence & 0xff;
  raw[3] = (sequence >> 8) & 0xff;
  raw[4] = body.length & 0xff;
  raw[5] = (body.length >> 8) & 0xff;
  raw.setRange(6, 6 + body.length, body);
  final crc = mmUartCrc16Ccitt(raw.sublist(0, raw.length - 2));
  raw[raw.length - 2] = crc & 0xff;
  raw[raw.length - 1] = (crc >> 8) & 0xff;

  final framed = mmUartCobsEncode(raw);
  return Uint8List.fromList([...framed, 0]);
}

MmUartFrame mmUartDecodeFrame(
  Iterable<int> encodedWithoutDelimiter, {
  bool allowUnknownVersion = false,
}) {
  final raw = mmUartCobsDecode(encodedWithoutDelimiter);
  if (raw.length < 8) throw const FormatException('FRAME_TOO_SHORT');
  final version = raw[0];
  if (!allowUnknownVersion && version != mmUartVersion) {
    throw const FormatException('UNSUPPORTED_VERSION');
  }
  final type = raw[1];
  final sequence = raw[2] | (raw[3] << 8);
  final payloadLength = raw[4] | (raw[5] << 8);
  if (raw.length != 6 + payloadLength + 2) {
    throw const FormatException('BAD_LENGTH');
  }
  final expected = raw[raw.length - 2] | (raw[raw.length - 1] << 8);
  final actual = mmUartCrc16Ccitt(raw.sublist(0, raw.length - 2));
  if (expected != actual) throw const FormatException('BAD_CRC');
  return MmUartFrame(
    version: version,
    type: type,
    sequence: sequence,
    payloadBytes: Uint8List.fromList(raw.sublist(6, 6 + payloadLength)),
  );
}

final class MmUartFrameStreamDecoder {
  MmUartFrameStreamDecoder({
    this.maxFrameLength = 65536,
    required this.onFrame,
    required this.onError,
  });

  final int maxFrameLength;
  final void Function(MmUartFrame frame) onFrame;
  final void Function(Object error) onError;
  final List<int> _buffer = [];

  void reset() => _buffer.clear();

  void push(Iterable<int> chunk) {
    for (final value in chunk) {
      final byte = value & 0xff;
      if (byte == 0) {
        if (_buffer.isEmpty) continue;
        final frameBytes = List<int>.from(_buffer);
        _buffer.clear();
        try {
          onFrame(mmUartDecodeFrame(frameBytes));
        } catch (error) {
          onError(error);
        }
      } else {
        _buffer.add(byte);
        if (_buffer.length > maxFrameLength) {
          _buffer.clear();
          onError(const FormatException('FRAME_TOO_LARGE'));
        }
      }
    }
  }
}
