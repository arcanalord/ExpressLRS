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

  test('MM-SERIAL survives one-byte-at-a-time USB reads', () {
    final codec = MmSerialCodec();
    final payload = Uint8List.fromList(
      List<int>.generate(257, (index) => index & 0xff),
    );
    final encoded = codec.encode(payload);

    final decoded = <Uint8List>[];
    for (final byte in encoded) {
      decoded.addAll(codec.feed(Uint8List.fromList(<int>[byte])));
    }

    expect(decoded, hasLength(1));
    expect(decoded.single, payload);
    expect(codec.badFrames, 0);
  });

  test('MM-SERIAL extracts multiple frames from one USB read', () {
    final codec = MmSerialCodec();
    final a = Uint8List.fromList(<int>[1, 0, 2, 3]);
    final b = Uint8List.fromList(<int>[9, 8, 0, 7, 6]);
    final merged = Uint8List.fromList(<int>[
      ...codec.encode(a),
      ...codec.encode(b),
    ]);

    final decoded = codec.feed(merged);
    expect(decoded, hasLength(2));
    expect(decoded[0], a);
    expect(decoded[1], b);
    expect(codec.badFrames, 0);
  });

  test('MM-SERIAL rejects CRC corruption then resynchronizes on next frame', () {
    final codec = MmSerialCodec();
    final badPayload = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final goodPayload = Uint8List.fromList(<int>[11, 12, 0, 13]);
    final bad = codec.encode(badPayload);
    bad[bad.length - 2] ^= 0x01;

    final decoded = codec.feed(
      Uint8List.fromList(<int>[...bad, ...codec.encode(goodPayload)]),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single, goodPayload);
    expect(codec.badFrames, 1);
    expect(codec.crcErrors, 1);
  });

  test('MM-SERIAL drops oversized garbage and recovers at delimiter', () {
    final codec = MmSerialCodec(maxFrameBytes: 16);
    final good = Uint8List.fromList(<int>[4, 3, 2, 1]);

    expect(
      codec.feed(Uint8List.fromList(List<int>.filled(32, 0x7f))),
      isEmpty,
    );
    expect(codec.oversizedFrames, greaterThanOrEqualTo(1));

    // A delimiter ends the garbage epoch; the next valid frame must parse.
    final decoded = codec.feed(
      Uint8List.fromList(<int>[0, ...codec.encode(good)]),
    );
    expect(decoded, hasLength(1));
    expect(decoded.single, good);
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
