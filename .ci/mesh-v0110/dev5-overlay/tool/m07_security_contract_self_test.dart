import '../lib/core/m07_security.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final encrypted = EncryptedApplicationEnvelope(
    formatVersion: 1,
    suiteId: 'provider-suite-v1',
    ciphertextBase64: 'ciphertext',
  );
  final wire = encrypted.encode();
  check(!wire.contains('mm:a') && !wire.contains('mm:b'),
      'M07 wire must not expose endpoint MM-IDs');
  check(!wire.contains('sessionId') && !wire.contains('logicalMessageId'),
      'M07 wire must not expose application/session correlation metadata');
  final internet = TransportPrivacyEnvelope(
    attemptId: 'internet-1',
    opaqueRoutingHandle: 'mailbox-random',
    wrappedPayloadBase64: encrypted.ciphertextBase64,
  );
  final radio = TransportPrivacyEnvelope(
    attemptId: 'radio-1',
    opaqueRoutingHandle: 'radio-route',
    wrappedPayloadBase64: encrypted.ciphertextBase64,
  );
  check(
    internet.wrappedPayloadBase64 == radio.wrappedPayloadBase64,
    'transport attempts must reuse one application ciphertext',
  );
  check(
    internet.attemptId != radio.attemptId,
    'route attempts must remain distinct',
  );

  final relayA = PairwiseRelayBinding(
    bindingId: 'b1',
    localContactMmId: 'mm:alice',
    relayId: 'relay-a',
    inboundHandle: 'queue-random-1',
    credentialRef: 'cred:1',
  );
  final relayB = PairwiseRelayBinding(
    bindingId: 'b2',
    localContactMmId: relayA.localContactMmId,
    relayId: 'relay-b',
    inboundHandle: 'queue-random-2',
    credentialRef: 'cred:2',
  );
  check(
    relayA.localContactMmId == relayB.localContactMmId,
    'relay rotation must not change identity',
  );
  check(
    relayA.inboundHandle != relayB.inboundHandle,
    'relay handles must be rotatable',
  );

  var rejected = false;
  try {
    IdentityPublicMaterial(
      formatVersion: 1,
      mmId: 'not-mm-id',
      fingerprint: 'fp',
      identityPublicKey: 'pk',
    );
  } on ArgumentError {
    rejected = true;
  }
  check(rejected, 'invalid identity shape must fail closed');

  final attachment = AttachmentCryptoRef(
    transferId: 't1',
    keyHandle: 'secure-local-handle',
    encryptedManifestBase64: 'manifest',
  );
  check(
    attachment.keyHandle == 'secure-local-handle',
    'M05 must receive an opaque attachment key handle',
  );

  print('M07_SECURITY_CONTRACT_PASS');
}
