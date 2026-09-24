import '../lib/platform/radio_uart_probe.dart';

void main() {
  // CRSF frame: address, length, type, payload..., crc(type+payload).
  final body = <int>[0x14, 0x01, 0x02, 0x03, 0x04];
  final crc = CrsfFrameDetector.crc8DvbS2(body, 0, body.length);
  final frame = <int>[0xC8, body.length + 1, ...body, crc];

  assert(CrsfFrameDetector.containsValidFrame(frame));
  assert(
    CrsfFrameDetector.containsValidFrame(<int>[0x00, 0x55, ...frame, 0x99]),
  );

  final broken = List<int>.from(frame);
  broken[broken.length - 1] ^= 0x01;
  assert(!CrsfFrameDetector.containsValidFrame(broken));
  assert(!CrsfFrameDetector.containsValidFrame(<int>[0xC8, 0x40, 0x14, 0x00]));

  print('radio UART probe self-test: PASS');
}
