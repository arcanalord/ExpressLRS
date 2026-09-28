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

  final hello = <String, Object?>{
    'v': 1,
    'p': 'MMRP/1',
    'k': 'hello',
    'from': 'mm:a',
    'to': '*',
    'label': 'Node A',
    'caps': const <String>['DIRECT/1', 'CHANNEL/1', 'GROUP/1'],
  };
  final helloDecoded = codec.feed(codec.encode(hello)).single;
  expectThat(helloDecoded['k'] == 'hello', 'hello kind roundtrip');
  expectThat(
    (helloDecoded['caps'] as List).contains('GROUP/1'),
    'hello capabilities roundtrip',
  );

  final descriptor = <String, Object?>{
    'v': 1,
    'p': 'MMRP/1',
    'k': 'group_descriptor',
    'from': 'mm:a',
    'to': 'mm:b',
    'group': 'g-1',
    'name': 'Field Team',
    'creator': 'mm:a',
    'members': const <String>['mm:a', 'mm:b'],
    'rev': 3,
    'createdAt': '2026-09-28T00:00:00.000Z',
    'updatedAt': '2026-09-28T00:00:01.000Z',
  };
  final descriptorDecoded = codec.feed(codec.encode(descriptor)).single;
  expectThat(
    descriptorDecoded['k'] == 'group_descriptor' &&
        descriptorDecoded['rev'] == 3,
    'group descriptor roundtrip',
  );

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
