import 'dart:convert';
import 'dart:typed_data';

sealed class Mmrp1ChannelFrame {
  const Mmrp1ChannelFrame({
    required this.from,
    required this.channel,
    required this.messageId,
  });

  final String from;
  final String channel;
  final String messageId;
}

final class Mmrp1ChannelData extends Mmrp1ChannelFrame {
  const Mmrp1ChannelData({
    required super.from,
    required super.channel,
    required super.messageId,
    this.messageClass = 'text',
    required this.payload,
  });

  final String messageClass;
  final String payload;
}

final class Mmrp1ChannelReceipt extends Mmrp1ChannelFrame {
  const Mmrp1ChannelReceipt({
    required super.from,
    required super.channel,
    required super.messageId,
  });
}

/// Byte-compatible MMRP/1 CHANNEL/1 codec based on the physically proven MM U1
/// compatibility path.
///
/// Wire JSON shapes:
/// channel_data:
/// {"v":1,"p":"MMRP/1","k":"channel_data","id":"...","from":"...",
///  "channel":"general","class":"text","payload":"..."}
/// channel_receipt:
/// {"v":1,"p":"MMRP/1","k":"channel_receipt","id":"...","from":"...",
///  "channel":"general"}
///
/// This is application compatibility framing, not production encryption.
final class Mmrp1ChannelCodec {
  const Mmrp1ChannelCodec();

  static const String protocol = 'MMRP/1';
  static const int version = 1;
  static const int maxFrameBytes = 4096;
  static const int maxTextBytes = 2048;

  Uint8List encode(Mmrp1ChannelFrame frame) {
    _validateId(frame.from, 'from');
    _validateToken(frame.channel, 'channel', 64);
    _validateId(frame.messageId, 'id');

    final Map<String, Object?> map;
    switch (frame) {
      case Mmrp1ChannelData():
        if (frame.messageClass != 'text') {
          throw const FormatException('only text channel data is supported');
        }
        final textBytes = utf8.encode(frame.payload);
        if (textBytes.isEmpty || textBytes.length > maxTextBytes) {
          throw const FormatException('invalid channel payload size');
        }
        map = <String, Object?>{
          'v': version,
          'p': protocol,
          'k': 'channel_data',
          'id': frame.messageId,
          'from': frame.from,
          'channel': frame.channel,
          'class': 'text',
          'payload': frame.payload,
        };
      case Mmrp1ChannelReceipt():
        map = <String, Object?>{
          'v': version,
          'p': protocol,
          'k': 'channel_receipt',
          'id': frame.messageId,
          'from': frame.from,
          'channel': frame.channel,
        };
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(map)));
    if (bytes.length > maxFrameBytes) {
      throw const FormatException('channel frame too large');
    }
    return bytes;
  }

  Mmrp1ChannelFrame? decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFrameBytes) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);

    if (map['v'] != version || map['p'] != protocol) return null;
    final kind = map['k'];
    final from = map['from'] is String ? (map['from'] as String).trim() : '';
    final channel =
        map['channel'] is String ? (map['channel'] as String).trim() : '';
    final id = map['id'] is String ? (map['id'] as String).trim() : '';
    if (!_validId(from) || !_validToken(channel, 64) || !_validId(id)) {
      return null;
    }

    if (kind == 'channel_data') {
      if (map['class'] != 'text' || map['payload'] is! String) return null;
      final payload = map['payload'] as String;
      final payloadBytes = utf8.encode(payload);
      if (payloadBytes.isEmpty || payloadBytes.length > maxTextBytes) {
        return null;
      }
      return Mmrp1ChannelData(
        from: from,
        channel: channel,
        messageId: id,
        payload: payload,
      );
    }

    if (kind == 'channel_receipt') {
      return Mmrp1ChannelReceipt(
        from: from,
        channel: channel,
        messageId: id,
      );
    }

    return null;
  }

  static void _validateId(String value, String field) {
    if (!_validId(value)) throw FormatException('invalid $field');
  }

  static void _validateToken(String value, String field, int maxLength) {
    if (!_validToken(value, maxLength)) {
      throw FormatException('invalid $field');
    }
  }

  static bool _validId(String value) =>
      value.trim().isNotEmpty && value.length <= 192;

  static bool _validToken(String value, int maxLength) =>
      value.isNotEmpty &&
      value.length <= maxLength &&
      value.codeUnits.every((code) => code >= 0x21 && code <= 0x7e);
}
