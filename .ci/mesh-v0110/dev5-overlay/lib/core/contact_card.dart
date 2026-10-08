import 'dart:convert';

import 'm07_security.dart';

final class ContactCard {
  const ContactCard({
    required this.mmId,
    required this.displayName,
    this.fingerprint,
    this.identityPublicKey,
    this.agreementPublicKey,
    this.preKeyBundle,
    this.meshtasticNodeId,
    this.radioNodeId,
    this.radioNodeBinding,
  });

  static const scheme = 'mesh';
  static const host = 'contact';
  static const version = 2;
  static const legacyVersion = 1;

  final String mmId;
  final String displayName;
  final String? fingerprint;
  final String? identityPublicKey;
  final String? agreementPublicKey;
  final String? preKeyBundle;
  final String? meshtasticNodeId;
  final int? radioNodeId;
  /// Routing hint only: this does not verify the contact's cryptographic keys.
  final String? radioNodeBinding;

  String encode() {
    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: <String, String>{
        'v': version.toString(),
        'mm': mmId.trim(),
        'name': displayName.trim(),
        if (fingerprint?.trim().isNotEmpty == true) 'fp': fingerprint!.trim(),
        if (identityPublicKey?.trim().isNotEmpty == true)
          'ik': identityPublicKey!.trim(),
        if (agreementPublicKey?.trim().isNotEmpty == true)
          'ak': agreementPublicKey!.trim(),
        if (preKeyBundle?.trim().isNotEmpty == true)
          'pkb': preKeyBundle!.trim(),
        if (meshtasticNodeId?.trim().isNotEmpty == true)
          'mesh': meshtasticNodeId!.trim(),
        if (radioNodeId != null) 'radio': radioNodeId.toString(),
        if (radioNodeBinding?.trim().isNotEmpty == true)
          'm03': radioNodeBinding!.trim(),
      },
    );
    return uri.toString();
  }

  String encodeJson() => jsonEncode(<String, Object?>{
        'schema': 'mesh-messenger-contact/v2',
        'mmId': mmId.trim(),
        'displayName': displayName.trim(),
        if (fingerprint?.trim().isNotEmpty == true)
          'fingerprint': fingerprint!.trim(),
        if (identityPublicKey?.trim().isNotEmpty == true)
          'identityPublicKey': identityPublicKey!.trim(),
        if (agreementPublicKey?.trim().isNotEmpty == true)
          'agreementPublicKey': agreementPublicKey!.trim(),
        if (preKeyBundle?.trim().isNotEmpty == true)
          'preKeyBundle': preKeyBundle!.trim(),
        if (meshtasticNodeId?.trim().isNotEmpty == true)
          'meshtasticNodeId': meshtasticNodeId!.trim(),
        if (radioNodeId != null) 'radioNodeId': radioNodeId,
        if (radioNodeBinding?.trim().isNotEmpty == true)
          'radioNodeBinding': radioNodeBinding!.trim(),
      });

  static ContactCard parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) throw const FormatException('Empty contact card');

    if (text.startsWith('{')) {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unsupported contact card JSON');
      }
      final schema = decoded['schema'];
      if (schema != 'mesh-messenger-contact/v1' &&
          schema != 'mesh-messenger-contact/v2') {
        throw const FormatException('Unsupported contact card JSON');
      }
      return _validated(
        ContactCard(
          mmId: decoded['mmId'] as String? ?? '',
          displayName: decoded['displayName'] as String? ?? '',
          fingerprint: decoded['fingerprint'] as String?,
          identityPublicKey: decoded['identityPublicKey'] as String?,
          agreementPublicKey: decoded['agreementPublicKey'] as String?,
          preKeyBundle: decoded['preKeyBundle'] as String?,
          meshtasticNodeId: decoded['meshtasticNodeId'] as String?,
          radioNodeId: (decoded['radioNodeId'] as num?)?.toInt(),
          radioNodeBinding: decoded['radioNodeBinding'] as String?,
        ),
      );
    }

    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != scheme || uri.host != host) {
      throw const FormatException('Unsupported contact card');
    }
    final q = uri.queryParameters;
    final parsedVersion = int.tryParse(q['v'] ?? '');
    if (parsedVersion != legacyVersion && parsedVersion != version) {
      throw const FormatException('Unsupported contact card version');
    }
    return _validated(
      ContactCard(
        mmId: q['mm'] ?? '',
        displayName: q['name'] ?? '',
        fingerprint: q['fp'],
        identityPublicKey: q['ik'],
        agreementPublicKey: q['ak'],
        preKeyBundle: q['pkb'],
        meshtasticNodeId: q['mesh'],
        radioNodeId: int.tryParse(q['radio'] ?? ''),
        radioNodeBinding: q['m03'],
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
    final identityKey = card.identityPublicKey?.trim() ?? '';
    final agreementKey = card.agreementPublicKey?.trim() ?? '';
    if ((identityKey.isEmpty) != (agreementKey.isEmpty)) {
      throw const FormatException('Identity/agreement public keys must appear together');
    }
    final bundle = card.preKeyBundle?.trim() ?? '';
    if (bundle.isNotEmpty) {
      final parsed = PortablePreKeyBundle.decode(bundle);
      if (parsed.mmId != card.mmId.trim()) {
        throw const FormatException('Prekey bundle MM-ID mismatch');
      }
      if (identityKey.isNotEmpty &&
          parsed.identityPublicKey != identityKey) {
        throw const FormatException('Prekey bundle identity mismatch');
      }
    }
    final node = card.radioNodeId;
    if (node != null && (node < 1 || node > 255)) {
      throw const FormatException('Invalid radio node ID');
    }
    final opaque = card.radioNodeBinding?.trim() ?? '';
    if (opaque.isNotEmpty &&
        !RegExp(r'^[A-Za-z0-9._:-]{1,64}
  }
}
).hasMatch(opaque)) {
      throw const FormatException('Invalid M03 radio node binding');
    }
    return card;
  }
}
