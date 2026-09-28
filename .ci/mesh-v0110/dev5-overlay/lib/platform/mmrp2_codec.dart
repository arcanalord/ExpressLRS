import 'dart:typed_data';

final class Mmrp2Codec {
  const Mmrp2Codec._();

  static const int version = 2;
  static const int baseHeaderBytes = 16;
  static const int fragmentExtensionBytes = 8;
  static const int hopAeadTagBytes = 16;
  static const int linkAckBodyBytes = 8;

  static const int flagAckRequested = 0x01;
  static const int flagFragmented = 0x02;
  static const int flagHopAead = 0x04;
  static const int flagStoreForwardEligible = 0x08;
  static const int flagPadded = 0x10;
  static const int flagRotateTagHint = 0x20;

  static const int _allowedFlags = 0x3f;
  static const int _reservedFlags = 0xc0;

  static Uint8List encodeHeader(Mmrp2Header header) {
    _validateHeader(header);
    final headerBytes = header.fragment == null
        ? baseHeaderBytes
        : baseHeaderBytes + fragmentExtensionBytes;
    final headerWords = headerBytes ~/ 4;
    final out = Uint8List(headerBytes);
    out[0] = (version << 4) | headerWords;
    out[1] = header.flags;
    out[2] = (header.frameClass.wire << 4) | header.trafficClass.wire;
    out[3] = (header.hopLimit << 4) | header.ttlClass;
    out.setRange(4, 12, header.routeTag);
    _writeU32(out, 12, header.packetCounter);
    final fragment = header.fragment;
    if (fragment != null) {
      _writeU32(out, 16, fragment.fragmentGroupId);
      _writeU16(out, 20, fragment.fragmentIndex);
      _writeU16(out, 22, fragment.fragmentCount);
    }
    return out;
  }

  static Mmrp2Header decodeHeader(Uint8List bytes) {
    if (bytes.length < baseHeaderBytes) {
      throw const FormatException('MMRP/2 frame shorter than base header');
    }
    final first = bytes[0];
    final decodedVersion = first >> 4;
    final headerWords = first & 0x0f;
    if (decodedVersion != version) {
      throw FormatException('Unsupported MMRP version: $decodedVersion');
    }
    if (headerWords < 4 || headerWords > 15) {
      throw FormatException('Invalid MMRP/2 header_words: $headerWords');
    }
    final headerBytes = headerWords * 4;
    if (headerBytes > bytes.length) {
      throw const FormatException('Truncated MMRP/2 header');
    }

    final flags = bytes[1];
    if ((flags & _reservedFlags) != 0) {
      throw const FormatException('Reserved MMRP/2 flag bits are set');
    }
    final fragmented = (flags & flagFragmented) != 0;
    final expectedHeaderBytes = fragmented
        ? baseHeaderBytes + fragmentExtensionBytes
        : baseHeaderBytes;
    if (headerBytes != expectedHeaderBytes) {
      throw const FormatException(\n        'Unknown or malformed MMRP/2 header extension',\n      );
    }

    final classTraffic = bytes[2];
    final frameClass = Mmrp2FrameClass.fromWire(classTraffic >> 4);
    final trafficClass = Mmrp2TrafficClass.fromWire(classTraffic & 0x0f);
    final hopTtl = bytes[3];
    final hopLimit = hopTtl >> 4;
    final ttlClass = hopTtl & 0x0f;
    if (ttlClass > 7) {
      throw FormatException('Reserved MMRP/2 ttl_class: $ttlClass');
    }

    final routeTag = Uint8List.fromList(bytes.sublist(4, 12));
    if (_allZero(routeTag) &&
        frameClass != Mmrp2FrameClass.discovery &&
        frameClass != Mmrp2FrameClass.capability) {
      throw const FormatException(
        'route_tag=0 is only valid for broadcast discovery/capability',
      );
    }

    Mmrp2Fragment? fragment;
    if (fragmented) {
      fragment = Mmrp2Fragment(
        fragmentGroupId: _readU32(bytes, 16),
        fragmentIndex: _readU16(bytes, 20),
        fragmentCount: _readU16(bytes, 22),
      );
      _validateFragment(fragment);
    }

    return Mmrp2Header(
      flags: flags,
      frameClass: frameClass,
      trafficClass: trafficClass,
      hopLimit: hopLimit,
      ttlClass: ttlClass,
      routeTag: routeTag,
      packetCounter: _readU32(bytes, 12),
      fragment: fragment,
    );
  }

  static Uint8List encodePacket(
    Mmrp2Packet packet, {
    int maxFrameBytes = 65535,
    int maxPayloadBytes = 65535,
  }) {
    if (maxFrameBytes < baseHeaderBytes) {
      throw RangeError('maxFrameBytes too small');
    }
    if (maxPayloadBytes < 0 || packet.payload.length > maxPayloadBytes) {
      throw RangeError('MMRP/2 payload exceeds negotiated limit');
    }

    final header = encodeHeader(packet.header);
    final hopAead = (packet.header.flags & flagHopAead) != 0;
    final tag = packet.hopAeadTag;
    if (hopAead) {
      if (tag == null || tag.length != hopAeadTagBytes) {
        throw const FormatException('HOP_AEAD requires an exact 16-byte tag');
      }
    } else if (tag != null) {
      throw const FormatException('Hop AEAD tag present without HOP_AEAD flag');
    }

    final total = header.length + packet.payload.length + (tag?.length ?? 0);
    if (total > maxFrameBytes) {
      throw RangeError('MMRP/2 frame exceeds negotiated maxFrameBytes');
    }
    return Uint8List(total)
      ..setRange(0, header.length, header)
      ..setRange(\n        header.length,\n        header.length + packet.payload.length,\n        packet.payload,\n      )
      ..setRange(
        header.length + packet.payload.length,
        total,
        tag ?? const <int>[],
      );
  }

  static Mmrp2Packet decodePacket(
    Uint8List bytes, {
    int maxFrameBytes = 65535,
    int maxPayloadBytes = 65535,
  }) {
    if (bytes.length > maxFrameBytes) {
      throw RangeError('MMRP/2 frame exceeds negotiated maxFrameBytes');
    }
    final header = decodeHeader(bytes);
    final headerBytes = header.fragment == null
        ? baseHeaderBytes
        : baseHeaderBytes + fragmentExtensionBytes;
    final hopAead = (header.flags & flagHopAead) != 0;
    final tagBytes = hopAead ? hopAeadTagBytes : 0;
    if (bytes.length < headerBytes + tagBytes) {
      throw const FormatException('Truncated MMRP/2 frame/tag');
    }
    final payloadEnd = bytes.length - tagBytes;
    final payload = Uint8List.fromList(bytes.sublist(headerBytes, payloadEnd));
    if (payload.length > maxPayloadBytes) {
      throw RangeError('MMRP/2 payload exceeds negotiated limit');
    }
    if (header.frameClass == Mmrp2FrameClass.linkAck &&
        payload.length != linkAckBodyBytes) {
      throw const FormatException('LINK_ACK payload must be exactly 8 bytes');
    }
    return Mmrp2Packet(
      header: header,
      payload: payload,
      hopAeadTag: hopAead
          ? Uint8List.fromList(bytes.sublist(payloadEnd))
          : null,
    );
  }

  static Uint8List encodeLinkAckBody(Mmrp2LinkAck ack) {
    final out = Uint8List(linkAckBodyBytes);
    _writeU32(out, 0, ack.ackBaseCounter);
    _writeU32(out, 4, ack.ackBitmap);
    return out;
  }

  static Mmrp2LinkAck decodeLinkAckBody(Uint8List bytes) {
    if (bytes.length != linkAckBodyBytes) {
      throw const FormatException('LINK_ACK body must be exactly 8 bytes');
    }
    return Mmrp2LinkAck(
      ackBaseCounter: _readU32(bytes, 0),
      ackBitmap: _readU32(bytes, 4),
    );
  }

  static void _validateHeader(Mmrp2Header header) {
    if ((header.flags & _allowedFlags) != header.flags) {
      throw const FormatException('Reserved MMRP/2 flag bits are set');
    }
    if (header.hopLimit < 0 || header.hopLimit > 15) {
      throw RangeError.range(header.hopLimit, 0, 15, 'hopLimit');
    }
    if (header.ttlClass < 0 || header.ttlClass > 7) {
      throw RangeError.range(header.ttlClass, 0, 7, 'ttlClass');
    }
    if (header.routeTag.length != 8) {
      throw const FormatException('route_tag must be exactly 8 bytes');
    }
    final fragmented = (header.flags & flagFragmented) != 0;
    if (fragmented != (header.fragment != null)) {
      throw const FormatException(
        'FRAGMENTED flag and fragment extension must agree',
      );
    }
    if (header.fragment case final fragment?) {
      _validateFragment(fragment);
    }
    if (_allZero(header.routeTag) &&
        header.frameClass != Mmrp2FrameClass.discovery &&
        header.frameClass != Mmrp2FrameClass.capability) {
      throw const FormatException(
        'route_tag=0 is only valid for broadcast discovery/capability',
      );
    }
  }

  static void _validateFragment(Mmrp2Fragment fragment) {
    if (fragment.fragmentCount < 2 || fragment.fragmentCount > 0xffff) {
      throw RangeError('fragment_count must be 2..65535');
    }
    if (fragment.fragmentIndex < 0 ||
        fragment.fragmentIndex >= fragment.fragmentCount) {
      throw RangeError('fragment_index must be < fragment_count');
    }
  }

  static bool _allZero(List<int> bytes) => bytes.every((value) => value == 0);

  static void _writeU16(Uint8List out, int offset, int value) {
    if (value < 0 || value > 0xffff) throw RangeError.value(value);
    out[offset] = (value >> 8) & 0xff;
    out[offset + 1] = value & 0xff;
  }

  static int _readU16(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static void _writeU32(Uint8List out, int offset, int value) {
    if (value < 0 || value > 0xffffffff) throw RangeError.value(value);
    out[offset] = (value >> 24) & 0xff;
    out[offset + 1] = (value >> 16) & 0xff;
    out[offset + 2] = (value >> 8) & 0xff;
    out[offset + 3] = value & 0xff;
  }

  static int _readU32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

enum Mmrp2FrameClass {
  data(0),
  linkAck(1),
  control(2),
  discovery(3),
  capability(4),
  keepalivePadding(5),
  extension(15);

  const Mmrp2FrameClass(this.wire);
  final int wire;

  static Mmrp2FrameClass fromWire(int wire) => Mmrp2FrameClass.values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => throw FormatException(
          'Reserved/unknown MMRP/2 frame class: $wire',
        ),
      );
}

enum Mmrp2TrafficClass {
  urgentControl(0),
  interactive(1),
  bulk(2),
  background(3);

  const Mmrp2TrafficClass(this.wire);
  final int wire;

  static Mmrp2TrafficClass fromWire(int wire) =>
      Mmrp2TrafficClass.values.firstWhere(
        (value) => value.wire == wire,
        orElse: () => throw FormatException(
          'Reserved/unknown MMRP/2 traffic class: $wire',
        ),
      );
}

final class Mmrp2Fragment {
  const Mmrp2Fragment({
    required this.fragmentGroupId,
    required this.fragmentIndex,
    required this.fragmentCount,
  });

  final int fragmentGroupId;
  final int fragmentIndex;
  final int fragmentCount;
}

final class Mmrp2Header {
  const Mmrp2Header({
    required this.flags,
    required this.frameClass,
    required this.trafficClass,
    required this.hopLimit,
    required this.ttlClass,
    required this.routeTag,
    required this.packetCounter,
    this.fragment,
  });

  final int flags;
  final Mmrp2FrameClass frameClass;
  final Mmrp2TrafficClass trafficClass;
  final int hopLimit;
  final int ttlClass;
  final Uint8List routeTag;
  final int packetCounter;
  final Mmrp2Fragment? fragment;
}

final class Mmrp2Packet {
  const Mmrp2Packet({
    required this.header,
    this.payload = const <int>[],
    this.hopAeadTag,
  });

  final Mmrp2Header header;
  final List<int> payload;
  final List<int>? hopAeadTag;
}

final class Mmrp2LinkAck {
  const Mmrp2LinkAck({
    required this.ackBaseCounter,
    required this.ackBitmap,
  });

  final int ackBaseCounter;
  final int ackBitmap;
}

final class Mmrp2ReplayWindow {
  int? _highest;
  int _bitmap = 0;

  bool accept(int counter) {
    if (counter < 0 || counter > 0xffffffff) {
      throw RangeError.value(counter, 'counter');
    }
    final highest = _highest;
    if (highest == null) {
      _highest = counter;
      _bitmap = 1;
      return true;
    }
    if (counter > highest) {
      final shift = counter - highest;
      _bitmap = shift >= 64 ? 1 : ((_bitmap << shift) | 1) & 0xffffffffffffffff;
      _highest = counter;
      return true;
    }
    final delta = highest - counter;
    if (delta >= 64) return false;
    final bit = 1 << delta;
    if ((_bitmap & bit) != 0) return false;
    _bitmap |= bit;
    return true;
  }

  void resetForNewSecurityEpoch() {
    _highest = null;
    _bitmap = 0;
  }
}
