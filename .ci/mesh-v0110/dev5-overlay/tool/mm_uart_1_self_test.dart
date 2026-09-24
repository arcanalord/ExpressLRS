import 'dart:convert';
import '../lib/platform/mm_uart_1.dart';

void check(bool value, String message) { if (!value) throw StateError(message); }
String hex(Iterable<int> b) => b.map((e)=>e.toRadixString(16).padLeft(2,'0')).join();

void main() {
  check(MmUart1Codec.crc16Ccitt(utf8.encode('123456789')) == 0x29b1, 'CRC');
  final encoded = MmUart1Codec.encodeFrame(
    type: MmUart1FrameType.getInfo,
    sequence: 42,
    payload: {'hello':'мир','zero':0},
  );
  final fixture = hex(encoded);
  check(fixture == '0401022a021b1e7b2268656c6c6f223a22d0bcd0b8d180222c227a65726f223a307de6cb00', 'JS/Dart vector mismatch');
  final decoded = MmUart1Codec.decodeFrame(encoded.sublist(0, encoded.length - 1));
  check(decoded.sequence == 42, 'sequence');
  check((decoded.jsonPayload() as Map<String,dynamic>)['hello'] == 'мир', 'json');
  print('MM_UART_1_DART_COMPAT_PASS');
}
