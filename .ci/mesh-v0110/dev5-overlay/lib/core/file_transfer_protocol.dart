import 'dart:convert';
import 'dart:typed_data';

import 'file_transfer_core.dart';

enum File1FrameType {
  manifest(1),
  chunk(2),
  ack(3),
  missing(4),
  complete(5),
  error(6);

  const File1FrameType(this.code);
  final int code;

  static File1FrameType fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw FormatException('Unknown FILE/1 frame type: ' + code.toString());
  }
}

final class File1Frame {
  const File1Frame({
    required this.type,
    required this.transferId,
    required this.payload,
  });

  final File1FrameType type;
  final String transferId;
  final Uint8List payload;
}

final class File1Codec {
  const File1Codec._();

  static const List<int> magic = <int>[0x4d, 0x46, 0x31]; // MF1
  static const int maxTransferIdBytes = 96;
  static const int maxPayloadBytes = 64 * 1024;

  static Uint8List encode(File1Frame frame) {
    final transferIdBytes = utf8.encode(frame.transferId);
    if (transferIdBytes.isEmpty || transferIdBytes.length > maxTransferIdBytes) {
      throw const FormatException('Invalid FILE/1 transferId length');
    }
    if (frame.payload.length > maxPayloadBytes) {
      throw const FormatException('FILE/1 payload too large');
    }

    final out = BytesBuilder(copy: false);
    out.add(magic);
    out.addByte(frame.type.code);
    out.addByte(transferIdBytes.length);
    out.add(_u32(frame.payload.length));
    out.add(transferIdBytes);
    out.add(frame.payload);
    return out.takeBytes();
  }

  static File1Frame decode(Uint8List bytes) {
    const headerSize = 9;
    if (bytes.length < headerSize) {
      throw const FormatException('FILE/1 frame too short');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const FormatException('FILE/1 magic mismatch');
      }
    }

    final type = File1FrameType.fromCode(bytes[3]);
    final transferIdLength = bytes[4];
    final payloadLength = _readU32(bytes, 5);
    if (transferIdLength <= 0 || transferIdLength > maxTransferIdBytes) {
      throw const FormatException('Invalid FILE/1 transferId length');
    }
    if (payloadLength > maxPayloadBytes) {
      throw const FormatException('FILE/1 payload too large');
    }

    final expected = headerSize + transferIdLength + payloadLength;
    if (bytes.length != expected) {
      throw const FormatException('FILE/1 frame length mismatch');
    }

    final transferId = utf8.decode(bytes.sublist(headerSize, headerSize + transferIdLength));
    final payload = Uint8List.fromList(bytes.sublist(headerSize + transferIdLength));
    return File1Frame(type: type, transferId: transferId, payload: payload);
  }

  static File1Frame manifest(FileTransferManifest manifest) {
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson())));
    return File1Frame(
      type: File1FrameType.manifest,
      transferId: manifest.transferId,
      payload: payload,
    );
  }

  static FileTransferManifest decodeManifest(File1Frame frame) {
    _expect(frame, File1FrameType.manifest);
    final json = jsonDecode(utf8.decode(frame.payload));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid FILE/1 manifest payload');
    }
    final manifest = FileTransferManifest.fromJson(json);
    if (manifest.transferId != frame.transferId) {
      throw const FormatException('FILE/1 manifest transferId mismatch');
    }
    return manifest;
  }

  static File1Frame chunk(FileTransferChunk chunk) {
    final payload = BytesBuilder(copy: false)
      ..add(_u32(chunk.index))
      ..add(_u32(chunk.totalChunks))
      ..add(_u32(crc32(chunk.bytes)))
      ..add(chunk.bytes);
    return File1Frame(
      type: File1FrameType.chunk,
      transferId: chunk.transferId,
      payload: payload.takeBytes(),
    );
  }

  static FileTransferChunk decodeChunk(File1Frame frame) {
    _expect(frame, File1FrameType.chunk);
    if (frame.payload.length < 12) {
      throw const FormatException('FILE/1 chunk payload too short');
    }
    final index = _readU32(frame.payload, 0);
    final totalChunks = _readU32(frame.payload, 4);
    final expectedCrc = _readU32(frame.payload, 8);
    final data = Uint8List.fromList(frame.payload.sublist(12));
    if (crc32(data) != expectedCrc) {
      throw const FormatException('FILE/1 chunk CRC32 mismatch');
    }
    return FileTransferChunk(
      transferId: frame.transferId,
      index: index,
      totalChunks: totalChunks,
      bytes: data,
    );
  }

  static File1Frame ack(String transferId, int index) => File1Frame(
        type: File1FrameType.ack,
        transferId: transferId,
        payload: Uint8List.fromList(_u32(index)),
      );

  static int decodeAck(File1Frame frame) {
    _expect(frame, File1FrameType.ack);
    if (frame.payload.length != 4) {
      throw const FormatException('Invalid FILE/1 ACK payload');
    }
    return _readU32(frame.payload, 0);
  }

  static File1Frame missing(String transferId, Iterable<int> indexes) {
    final unique = indexes.toSet().toList()..sort();
    if (unique.length > 1024) {
      throw const FormatException('Too many FILE/1 missing indexes');
    }
    final payload = BytesBuilder(copy: false)
      ..add(<int>[(unique.length >> 8) & 0xff, unique.length & 0xff]);
    for (final index in unique) {
      if (index < 0) throw const FormatException('Negative missing index');
      payload.add(_u32(index));
    }
    return File1Frame(
      type: File1FrameType.missing,
      transferId: transferId,
      payload: payload.takeBytes(),
    );
  }

  static List<int> decodeMissing(File1Frame frame) {
    _expect(frame, File1FrameType.missing);
    if (frame.payload.length < 2) {
      throw const FormatException('Invalid FILE/1 missing payload');
    }
    final count = (frame.payload[0] << 8) | frame.payload[1];
    if (frame.payload.length != 2 + count * 4) {
      throw const FormatException('FILE/1 missing length mismatch');
    }
    return <int>[
      for (var i = 0; i < count; i++) _readU32(frame.payload, 2 + i * 4),
    ];
  }

  static File1Frame complete(String transferId) => File1Frame(
        type: File1FrameType.complete,
        transferId: transferId,
        payload: Uint8List(0),
      );

  static File1Frame error(String transferId, String message) {
    final bytes = utf8.encode(message);
    if (bytes.length > 512) {
      throw const FormatException('FILE/1 error text too long');
    }
    return File1Frame(
      type: File1FrameType.error,
      transferId: transferId,
      payload: Uint8List.fromList(bytes),
    );
  }

  static String decodeError(File1Frame frame) {
    _expect(frame, File1FrameType.error);
    return utf8.decode(frame.payload);
  }

  static int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte & 0xff;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0
            ? (crc >> 1) ^ 0xedb88320
            : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static void _expect(File1Frame frame, File1FrameType expected) {
    if (frame.type != expected) {
      throw FormatException(
        'Expected FILE/1 ' + expected.name + ', got ' + frame.type.name,
      );
    }
  }

  static List<int> _u32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff);
    }
    return <int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  static int _readU32(List<int> bytes, int offset) =>
      ((bytes[offset] << 24) |
              (bytes[offset + 1] << 16) |
              (bytes[offset + 2] << 8) |
              bytes[offset + 3]) &
          0xffffffff;
}
