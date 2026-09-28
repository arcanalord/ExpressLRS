import 'dart:convert';

final class ContactCard {
  const ContactCard({
    required this.mmId,
    required this.displayName,
    this.fingerprint,
    this.meshtasticNodeId,
    this.radioNodeId,
  });

  static const scheme = 'mesh';
  static const host = 'contact';
  static const version = 1;

  final String mmId;
  final String displayName;
  final String? fingerprint;
  final String? meshtasticNodeId;
  final int? radioNodeId;

  String encode() {
    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: <String, String>{
        'v': version.toString(),
        'mm': mmId.trim(),
        'name': displayName.trim(),
        if (fingerprint?.trim().isNotEmpty == true) 'fp': fingerprint!.trim(),
        if (meshtasticNodeId?.trim().isNotEmpty == true)
          'mesh': meshtasticNodeId!.trim(),
        if (radioNodeId != null) 'radio': radioNodeId.toString(),
      },
    );
    return uri.toString();
  }

  String encodeJson() => jsonEncode(<String, Object?>{
        'schema': 'mesh-messenger-contact/v1',
        'mmId': mmId.trim(),
        'displayName': displayName.trim(),
        if (fingerprint?.trim().isNotEmpty == true)
          'fingerprint': fingerprint!.trim(),
        if (meshtasticNodeId?.trim().isNotEmpty == true)
          'meshtasticNodeId': meshtasticNodeId!.trim(),
        if (radioNodeId != null) 'radioNodeId': radioNodeId,
      });

  static ContactCard parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) throw const FormatException('Empty contact card');

    if (text.startsWith('{')) {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != 'mesh-messenger-contact/v1') {
        throw const FormatException('Unsupported contact card JSON');
      }
      return _validated(
        ContactCard(
          mmId: decoded['mmId'] as String? ?? '',
          displayName: decoded['displayName'] as String? ?? '',
          fingerprint: decoded['fingerprint'] as String?,
          meshtasticNodeId: decoded['meshtasticNodeId'] as String?,
          radioNodeId: (decoded['radioNodeId'] as num?)?.toInt(),
        ),
      );
    }

    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != scheme || uri.host != host) {
      throw const FormatException('Unsupported contact card');
    }
    final q = uri.queryParameters;
    if (q['v'] != version.toString()) {
      throw const FormatException('Unsupported contact card version');
    }
    return _validated(
      ContactCard(
        mmId: q['mm'] ?? '',
        displayName: q['name'] ?? '',
        fingerprint: q['fp'],
        meshtasticNodeId: q['mesh'],
        radioNodeId: int.tryParse(q['radio'] ?? ''),
      ),
    );
  }

  static ContactCard _validated(ContactCard card) {
    if (!RegExp(r'^mm:[0-9A-Za-z._:-]{4,128}$').hasMatch(card.mmId.trim())) {
      throw const FormatException('Invalid MM-ID');
    }
    if (card.displayName.trim().isEmpty || card.displayName.length > 80) {
      throw const FormatException('Invalid contact name');
    }
    final node = card.radioNodeId;
    if (node != null && (node < 1 || node > 255)) {
      throw const FormatException('Invalid radio node ID');
    }
    return card;
  }
}
