import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/m03/mm_serial_codec.dart';

void main() {
  test('MM-SERIAL/1 is plain COBS(payload+CRC16)+delimiter', () {
    final codec = MmSerialCodec();
    final payload = Uint8List.fromList(<int>[
      0x7b, 0x22, 0x70, 0x22, 0x3a, 0x22, 0x4d, 0x4d, 0x52, 0x50,
      0x2f, 0x31, 0x22, 0x7d,
    ]);

    final encoded = codec.encode(payload);
    expect(encoded.last, 0);
    expect(encoded, _mmU1ReferenceEncode(payload));

    final decoded = codec.feed(encoded);
    expect(decoded, hasLength(1));
    expect(decoded.single, payload);
    expect(codec.badFrames, 0);
  });

  test('MM-SERIAL rejects CRC corruption and classifies it', () {
    final codec = MmSerialCodec();
    final payload = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final encoded = codec.encode(payload);
    encoded[encoded.length - 2] ^= 0x01;

    expect(codec.feed(encoded), isEmpty);
    expect(codec.badFrames, 1);
    expect(codec.crcErrors, 1);
  });
}

Uint8List _mmU1ReferenceEncode(Uint8List payload) {
  final crc = MmSerialCodec.crc16Ccitt(payload);
  final withCrc = Uint8List(payload.length + 2)
    ..setRange(0, payload.length, payload)
    ..[payload.length] = (crc >> 8) & 0xff
    ..[payload.length + 1] = crc & 0xff;
  return Uint8List.fromList(
    <int>[...MmSerialCodec.cobsEncode(withCrc), 0],
  );
}
