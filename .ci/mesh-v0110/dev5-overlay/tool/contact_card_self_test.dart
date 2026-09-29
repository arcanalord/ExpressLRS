import 'dart:io';

import '../lib/core/contact_card.dart';
import '../lib/core/m07_security.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final bundle = PortablePreKeyBundle(
    formatVersion: 1,
    bundleId: 'bundle-mm:abcd1234',
    mmId: 'mm:abcd1234',
    deviceId: 'device-1',
    epoch: 1,
    identityPublicKey: 'identity-pk',
    signedPreKeyId: 'spk-1',
    signedPreKeyPublic: 'signed-prekey',
    signedPreKeySignature: 'signature',
    expiresAtEpochMs: DateTime.utc(2030).millisecondsSinceEpoch,
    suiteProfile: M07SuiteProfile(
      identityAuthSuite: 'identity-v1',
      handshakeSuite: 'handshake-v1',
      ratchetSuite: 'ratchet-v1',
      attachmentSuite: 'attachment-v1',
      transportPrivacySuite: 'route-v1',
    ),
  );

  final card = ContactCard(
    mmId: 'mm:abcd1234',
    displayName: 'Tablet',
    fingerprint: 'AA:BB',
    identityPublicKey: 'identity-pk',
    agreementPublicKey: 'agreement-pk',
    preKeyBundle: bundle.encode(),
    meshtasticNodeId: '!1234abcd',
    radioNodeId: 2,
  );
  final parsed = ContactCard.parse(card.encode());
  check(parsed.mmId == card.mmId, 'URI MM-ID roundtrip failed');
  check(parsed.displayName == card.displayName, 'URI name roundtrip failed');
  check(parsed.radioNodeId == 2, 'URI radio node roundtrip failed');
  check(
    parsed.identityPublicKey == 'identity-pk' &&
        parsed.agreementPublicKey == 'agreement-pk',
    'M07 identity material roundtrip failed',
  );
  check(
    PortablePreKeyBundle.decode(parsed.preKeyBundle!).mmId == card.mmId,
    'M07 prekey bundle roundtrip failed',
  );

  final jsonParsed = ContactCard.parse(card.encodeJson());
  check(jsonParsed.fingerprint == 'AA:BB', 'JSON fingerprint roundtrip failed');
  check(
    jsonParsed.identityPublicKey == 'identity-pk',
    'JSON identity key roundtrip failed',
  );

  final legacy = ContactCard.parse(
    'mesh://contact?v=1&mm=mm%3Alegacy01&name=Legacy&fp=OLD',
  );
  check(legacy.mmId == 'mm:legacy01', 'v1 contact card must remain readable');
  check(legacy.identityPublicKey == null, 'v1 must stay legacy/no key material');

  var rejected = false;
  try {
    ContactCard.parse('https://example.com/');
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'Invalid contact payload accepted');

  var mismatchedBundleRejected = false;
  try {
    ContactCard.parse(
      ContactCard(
        mmId: 'mm:other01',
        displayName: 'Wrong bundle',
        identityPublicKey: 'identity-pk',
        agreementPublicKey: 'agreement-pk',
        preKeyBundle: bundle.encode(),
      ).encode(),
    );
  } on FormatException {
    mismatchedBundleRejected = true;
  }
  check(mismatchedBundleRejected, 'prekey/MM-ID mismatch accepted');

  stdout.writeln('MESH_MESSENGER_CONTACT_CARD_SELF_TEST_PASS');
}
