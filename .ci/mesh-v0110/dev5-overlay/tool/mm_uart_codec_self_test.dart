import 'dart:convert';

import '../lib/platform/mm_uart_codec.dart';

void main() {
  final known = mmUartCrc16Ccitt(utf8.encode('123456789'));
  if (known != 0x29b1) throw StateError('CRC vector failed: $known');

  final raw = <int>[1, 0, 2, 3, 0, 0, 4, 255];
  final roundtrip = mmUartCobsDecode(mmUartCobsEncode(raw));
  if (jsonEncode(roundtrip) != jsonEncode(raw)) {
    throw StateError('COBS roundtrip failed');
  }

  final frame = mmUartEncodeFrame(
    type: MmUartFrameType.getInfo,
    sequence: 42,
    payload: {'hello': 'мир', 'zero': 0},
  );
  if (frame.last != 0) throw StateError('frame delimiter missing');
  final decoded = mmUartDecodeFrame(frame.sublist(0, frame.length - 1));
  if (decoded.sequence != 42 || decoded.type != MmUartFrameType.getInfo) {
    throw StateError('frame header roundtrip failed');
  }
  final payload = decoded.decodeJsonPayload() as Map;
  if (payload['hello'] != 'мир' || payload['zero'] != 0) {
    throw StateError('JSON payload roundtrip failed');
  }

  final corrupt = frame.sublist(0, frame.length - 1).toList();
  corrupt[3] ^= 1;
  var crcRejected = false;
  try {
    mmUartDecodeFrame(corrupt);
  } catch (_) {
    crcRejected = true;
  }
  if (!crcRejected) throw StateError('corrupt frame was accepted');

  print('MM_UART_DART_CODEC_PASS');
  print(
    'FRAME_HEX=${frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
  );
}
