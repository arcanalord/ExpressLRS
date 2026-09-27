import 'dart:typed_data';

import '../lib/platform/mm_serial_codec.dart';

void expectThat(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void main() {
  final codec = MmSerialCodec();
  final frame = <String, Object?>{
    'v': 1,
    'p': 'MMRP/1',
    'k': 'data',
    'id': 'm-1',
    'from': 'mm:a',
    'to': 'mm:b',
    'class': 'text',
    'payload': 'Привет LR24',
  };

  final encoded = codec.encode(frame);
  expectThat(encoded.last == 0, 'delimiter');

  final split = encoded.length ~/ 2;
  expectThat(
    codec.feed(Uint8List.sublistView(encoded, 0, split)).isEmpty,
    'partial read must not emit',
  );
  final decoded = codec.feed(Uint8List.sublistView(encoded, split));
  expectThat(decoded.length == 1, 'partial reassembly');
  expectThat(decoded.single['payload'] == 'Привет LR24', 'payload roundtrip');

  final two = Uint8List.fromList(<int>[...encoded, ...encoded]);
  final decodedTwo = codec.feed(two);
  expectThat(decodedTwo.length == 2, 'multiple frames per read');

  final broken = Uint8List.fromList(encoded);
  if (broken.length > 5) broken[3] ^= 0x01;
  final before = codec.badFrames;
  codec.feed(broken);
  expectThat(codec.badFrames > before, 'CRC/corruption must be rejected');

  final payload = Uint8List.fromList(<int>[0, 1, 0, 2, 3, 0, 255]);
  final cobs = MmSerialCodec.cobsEncode(payload);
  final raw = MmSerialCodec.cobsDecode(cobs);
  expectThat(
    raw.length == payload.length &&
        List<int>.generate(payload.length, (i) => i)
            .every((i) => raw[i] == payload[i]),
    'COBS roundtrip',
  );

  print('MM_SERIAL_LR24_CODEC_PASS');
}
