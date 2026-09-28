import 'dart:typed_data';

import '../lib/platform/mmrp2_codec.dart';

void main() {
  final vectorA = Mmrp2Header(
    flags: 0,
    frameClass: Mmrp2FrameClass.data,
    trafficClass: Mmrp2TrafficClass.interactive,
    hopLimit: 3,
    ttlClass: 0,
    routeTag: _hex('1122334455667788'),
    packetCounter: 0x01020304,
  );
  _expectHex(
    Mmrp2Codec.encodeHeader(vectorA),
    '24000130112233445566778801020304',
    'vector A',
  );
  _assertRoundTrip(vectorA);

  final vectorB = Mmrp2Header(
    flags: Mmrp2Codec.flagHopAead,
    frameClass: Mmrp2FrameClass.data,
    trafficClass: Mmrp2TrafficClass.interactive,
    hopLimit: 1,
    ttlClass: 1,
    routeTag: _hex('8877665544332211'),
    packetCounter: 42,
  );
  _expectHex(
    Mmrp2Codec.encodeHeader(vectorB),
    '2404011188776655443322110000002a',
    'vector B',
  );
  final bPacket = Mmrp2Packet(
    header: vectorB,
    payload: _hex('deadbeef'),
    hopAeadTag: Uint8List.fromList(List<int>.generate(16, (i) => i)),
  );
  final bDecoded = Mmrp2Codec.decodePacket(Mmrp2Codec.encodePacket(bPacket));
  _expectHex(Uint8List.fromList(bDecoded.payload), 'deadbeef', 'vector B payload');

  final vectorC = Mmrp2Header(
    flags: Mmrp2Codec.flagFragmented | Mmrp2Codec.flagHopAead,
    frameClass: Mmrp2FrameClass.data,
    trafficClass: Mmrp2TrafficClass.bulk,
    hopLimit: 2,
    ttlClass: 2,
    routeTag: _hex('0102030405060708'),
    packetCounter: 16,
    fragment: const Mmrp2Fragment(
      fragmentGroupId: 0xa1b2c3d4,
      fragmentIndex: 1,
      fragmentCount: 3,
    ),
  );
  _expectHex(
    Mmrp2Codec.encodeHeader(vectorC),
    '26060222010203040506070800000010a1b2c3d400010003',
    'vector C',
  );
  _assertRoundTrip(vectorC);

  final vectorD = Mmrp2Header(
    flags: Mmrp2Codec.flagHopAead,
    frameClass: Mmrp2FrameClass.linkAck,
    trafficClass: Mmrp2TrafficClass.urgentControl,
    hopLimit: 1,
    ttlClass: 0,
    routeTag: _hex('0f0e0d0c0b0a0908'),
    packetCounter: 32,
  );
  _expectHex(
    Mmrp2Codec.encodeHeader(vectorD),
    '240410100f0e0d0c0b0a090800000020',
    'vector D',
  );
  final ack = Mmrp2LinkAck(ackBaseCounter: 31, ackBitmap: 7);
  _expectHex(
    Mmrp2Codec.encodeLinkAckBody(ack),
    '0000001f00000007',
    'LINK_ACK body',
  );

  final base = _hex('24000130112233445566778801020304');
  _expectReject(Uint8List.fromList(base)..[0] = 0x23, 'N1');
  _expectReject(Uint8List.fromList(base)..[1] = 0x80, 'N2');
  final n3 = Uint8List.fromList(base);
  for (var i = 4; i < 12; i++) {
    n3[i] = 0;
  }
  _expectReject(n3, 'N3');
  _expectReject(
    Uint8List.fromList(base)..[1] = Mmrp2Codec.flagFragmented,
    'N4',
  );
  _expectReject(
    _hex('26060222010203040506070800000010a1b2c3d400010001'),
    'N5',
  );

  final replay = Mmrp2ReplayWindow();
  _check(replay.accept(100), 'replay first');
  _check(!replay.accept(100), 'replay duplicate');
  _check(replay.accept(102), 'replay forward');
  _check(replay.accept(101), 'replay out-of-order');
  _check(!replay.accept(101), 'replay out-of-order duplicate');
  _check(replay.accept(200), 'replay large advance');
  _check(!replay.accept(100), 'replay too old');
  replay.resetForNewSecurityEpoch();
  _check(replay.accept(100), 'replay reset');

  var missingTagRejected = false;
  try {
    Mmrp2Codec.encodePacket(
      Mmrp2Packet(header: vectorB, payload: const <int>[1]),
    );
  } on FormatException {
    missingTagRejected = true;
  }
  _check(missingTagRejected, 'missing HOP_AEAD tag');

  print('MMRP2_DART_GOLDEN_VECTOR_PASS');
}

void _assertRoundTrip(Mmrp2Header expected) {
  final decoded = Mmrp2Codec.decodeHeader(Mmrp2Codec.encodeHeader(expected));
  _check(decoded.flags == expected.flags, 'flags');
  _check(decoded.frameClass == expected.frameClass, 'frame class');
  _check(decoded.trafficClass == expected.trafficClass, 'traffic class');
  _check(decoded.hopLimit == expected.hopLimit, 'hop limit');
  _check(decoded.ttlClass == expected.ttlClass, 'ttl class');
  _expectHex(decoded.routeTag, _toHex(expected.routeTag), 'route tag');
  _check(decoded.packetCounter == expected.packetCounter, 'counter');
  _check(
    decoded.fragment?.fragmentGroupId == expected.fragment?.fragmentGroupId &&
        decoded.fragment?.fragmentIndex == expected.fragment?.fragmentIndex &&
        decoded.fragment?.fragmentCount == expected.fragment?.fragmentCount,
    'fragment',
  );
}

void _expectReject(Uint8List bytes, String name) {
  var rejected = false;
  try {
    Mmrp2Codec.decodeHeader(bytes);
  } on FormatException {
    rejected = true;
  } on RangeError {
    rejected = true;
  }
  _check(rejected, '$name should reject');
}

void _expectHex(Uint8List actual, String expected, String label) {
  final value = _toHex(actual);
  if (value != expected.toLowerCase()) {
    throw StateError('$label mismatch: $value != $expected');
  }
}

Uint8List _hex(String input) {
  final normalized = input.replaceAll(' ', '').toLowerCase();
  if (normalized.length.isOdd) throw StateError('odd hex length');
  return Uint8List.fromList(
    List<int>.generate(
      normalized.length ~/ 2,
      (i) => int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

String _toHex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

void _check(bool value, String label) {
  if (!value) throw StateError('MMRP/2 self-test failed: $label');
}
