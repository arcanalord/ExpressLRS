import 'dart:io';

import '../lib/core/contact_card.dart';

void main() {
  const card = ContactCard(
    mmId: 'mm:abcd1234',
    displayName: 'Tablet',
    fingerprint: 'AA:BB',
    meshtasticNodeId: '!1234abcd',
    radioNodeId: 2,
  );
  final parsed = ContactCard.parse(card.encode());
  if (parsed.mmId != card.mmId ||
      parsed.displayName != card.displayName ||
      parsed.radioNodeId != 2) {
    throw StateError('URI contact card roundtrip failed');
  }
  final jsonParsed = ContactCard.parse(card.encodeJson());
  if (jsonParsed.fingerprint != 'AA:BB') {
    throw StateError('JSON contact card roundtrip failed');
  }
  var rejected = false;
  try {
    ContactCard.parse('https://example.com/');
  } on FormatException {
    rejected = true;
  }
  if (!rejected) throw StateError('Invalid contact payload accepted');
  stdout.writeln('MESH_MESSENGER_CONTACT_CARD_SELF_TEST_PASS');
}
