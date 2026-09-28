import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/app_storage.dart';
import '../lib/core/delivery.dart';
import '../lib/core/m07_security.dart';
import '../lib/core/messenger_core.dart';
import '../lib/core/models.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final class _CaptureTransport implements MessageTransport {
  _CaptureTransport(this.id, {this.result = TransportSendStatus.accepted});

  @override
  final String id;
  final TransportSendStatus result;
  final List<DeliveryEnvelope> sent = <DeliveryEnvelope>[];

  @override
  bool get isAvailable => true;

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    sent.add(envelope);
    return TransportSendResult(result);
  }
}

/// Deterministic wiring-only provider.
///
/// This is deliberately NOT production cryptography. It exists only to prove
/// that M07 owns private plaintext and transports receive one immutable opaque
/// application envelope.
final class _TestM07Provider implements M07CryptoProvider {
  _TestM07Provider(this.mmId);

  final String mmId;
  int encryptCalls = 0;
  final Map<String, PortablePreKeyBundle> peerBundles =
      <String, PortablePreKeyBundle>{};

  @override
  M07SuiteProfile get suiteProfile => M07SuiteProfile(
    identityAuthSuite: 'test-identity-v1',
    handshakeSuite: 'test-handshake-v1',
    ratchetSuite: 'test-ratchet-v1',
    attachmentSuite: 'test-attachment-v1',
    transportPrivacySuite: 'test-route-v1',
  );

  @override
  IdentityPublicMaterial localIdentity() => IdentityPublicMaterial(
    formatVersion: 1,
    mmId: mmId,
    fingerprint: 'fp-$mmId',
    identityPublicKey: 'pk-$mmId',
  );

  @override
  Future<PortablePreKeyBundle> localPreKeyBundle() async =>
      PortablePreKeyBundle(
        formatVersion: 1,
        bundleId: 'bundle-$mmId',
        mmId: mmId,
        deviceId: 'device-1',
        epoch: 1,
        identityPublicKey: 'pk-$mmId',
        signedPreKeyId: 'spk-1',
        signedPreKeyPublic: 'spk-public-$mmId',
        signedPreKeySignature: 'sig-$mmId',
        oneTimePreKeyId: 'opk-1',
        oneTimePreKeyPublic: 'opk-public-$mmId',
        expiresAtEpochMs:
            DateTime.utc(2030, 1, 1).millisecondsSinceEpoch,
        suiteProfile: suiteProfile,
      );

  @override
  Future<void> importPeerPreKeyBundle(PortablePreKeyBundle bundle) async {
    peerBundles[bundle.mmId] = bundle;
  }

  @override
  bool verifyIdentityBinding(IdentityPublicMaterial identity) =>
      identity.identityPublicKey == 'pk-${identity.mmId}' &&
      identity.fingerprint == 'fp-${identity.mmId}';

  @override
  Future<SecureSessionRef> ensureDirectSession(
    IdentityPublicMaterial peer, {
    PortablePreKeyBundle? preKeyBundle,
  }) async =>
      SecureSessionRef(
        sessionId: 'session:$mmId->${peer.mmId}',
        peerMmId: peer.mmId,
        suiteId: suiteProfile.ratchetSuite,
      );

  @override
  Future<EncryptedApplicationEnvelope> encryptDirect(
    DirectPlaintext plaintext,
  ) async {
    encryptCalls += 1;
    final packed = jsonEncode(<String, Object?>{
      'logicalMessageId': plaintext.logicalMessageId,
      'senderMmId': plaintext.senderMmId,
      'recipientMmId': plaintext.recipientMmId,
      'conversationKey': plaintext.conversationKey,
      'messageClass': plaintext.messageClass,
      'payloadUtf8': plaintext.payloadUtf8,
    });
    return EncryptedApplicationEnvelope(
      formatVersion: 1,
      suiteId: suiteProfile.ratchetSuite,
      logicalMessageId: plaintext.logicalMessageId,
      senderMmId: plaintext.senderMmId,
      recipientMmId: plaintext.recipientMmId,
      sessionId: 'session:${plaintext.senderMmId}->${plaintext.recipientMmId}',
      ciphertextBase64: base64UrlEncode(utf8.encode(packed)),
    );
  }

  @override
  Future<DirectDecryptResult> decryptDirect(
    EncryptedApplicationEnvelope envelope,
  ) async {
    if (envelope.recipientMmId != mmId) {
      return const DirectDecryptRejected('wrong_recipient');
    }
    try {
      final raw = jsonDecode(
        utf8.decode(base64Url.decode(envelope.ciphertextBase64)),
      );
      if (raw is! Map) return const DirectDecryptRejected('invalid_payload');
      final map = Map<String, dynamic>.from(raw);
      return DirectDecryptSuccess(
        DirectPlaintext(
          logicalMessageId: map['logicalMessageId'] as String,
          senderMmId: map['senderMmId'] as String,
          recipientMmId: map['recipientMmId'] as String,
          conversationKey: map['conversationKey'] as String,
          messageClass: map['messageClass'] as String,
          payloadUtf8: map['payloadUtf8'] as String,
        ),
      );
    } catch (_) {
      return const DirectDecryptRejected('invalid_payload');
    }
  }

  @override
  Future<AttachmentCryptoRef> createAttachmentCrypto(
    SecureSessionRef session,
    AttachmentManifest manifest,
  ) async =>
      AttachmentCryptoRef(
        transferId: manifest.transferId,
        keyHandle: 'test-only-handle',
        encryptedManifestBase64: base64UrlEncode(utf8.encode(manifest.contentHash)),
      );

  @override
  Future<Uint8List> encryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List plaintext,
  ) async =>
      Uint8List.fromList(plaintext);

  @override
  Future<Uint8List> decryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List ciphertext,
  ) async =>
      Uint8List.fromList(ciphertext);
}

Contact _contact(String mmId) => Contact(
  mmId: mmId,
  displayName: mmId,
  verified: true,
  identityPublicKey: 'pk-$mmId',
  fingerprint: 'fp-$mmId',
);

Future<void> main() async {
  final aliceRoot = Directory.systemTemp.createTempSync('m07-alice-');
  final bobRoot = Directory.systemTemp.createTempSync('m07-bob-');
  final malloryRoot = Directory.systemTemp.createTempSync('m07-mallory-');
  try {
    final aliceStorage = AppStorage(aliceRoot);
    final bobStorage = AppStorage(bobRoot);
    final malloryStorage = AppStorage(malloryRoot);
    await aliceStorage.saveContact(_contact('mm:bob'));
    await bobStorage.saveContact(_contact('mm:alice'));

    final aliceProvider = _TestM07Provider('mm:alice');
    final bobProvider = _TestM07Provider('mm:bob');
    final malloryProvider = _TestM07Provider('mm:mallory');

    await aliceProvider.importPeerPreKeyBundle(
      await bobProvider.localPreKeyBundle(),
    );
    await bobProvider.importPeerPreKeyBundle(
      await aliceProvider.localPreKeyBundle(),
    );

    final rejectRoute = _CaptureTransport(
      'route-a',
      result: TransportSendStatus.rejected,
    );
    final acceptRoute = _CaptureTransport('route-b');
    final alice = MeshMessengerCore(
      ownMmId: 'mm:alice',
      storage: aliceStorage,
      transports: <MessageTransport>[rejectRoute, acceptRoute],
      cryptoProvider: aliceProvider,
      requirePrivateE2ee: true,
      now: () => DateTime.utc(2026, 9, 28, 12),
    );
    final bob = MeshMessengerCore(
      ownMmId: 'mm:bob',
      storage: bobStorage,
      transports: const <MessageTransport>[],
      cryptoProvider: bobProvider,
      requirePrivateE2ee: true,
      now: () => DateTime.utc(2026, 9, 28, 12),
    );
    final mallory = MeshMessengerCore(
      ownMmId: 'mm:mallory',
      storage: malloryStorage,
      transports: const <MessageTransport>[],
      cryptoProvider: malloryProvider,
      requirePrivateE2ee: true,
    );

    const secret = 'private hello over any route';
    final sent = await alice.sendText(peerMmId: 'mm:bob', text: secret);
    check(sent.messageClass == m07DirectEnvelopeClass, 'M07 class required');
    check(aliceProvider.encryptCalls == 1, 'ratchet/encrypt must advance once');
    check(rejectRoute.sent.length == 1 && acceptRoute.sent.length == 1,
        'both route attempts must see one envelope');
    check(
      rejectRoute.sent.single.payload == acceptRoute.sent.single.payload,
      'transport attempts must reuse identical ciphertext',
    );
    check(
      !acceptRoute.sent.single.payload.contains(secret),
      'transport payload must not contain private plaintext',
    );

    final outer = acceptRoute.sent.single;
    final parsed = EncryptedApplicationEnvelope.decode(outer.payload);
    check(parsed.logicalMessageId == outer.messageId, 'message id binding');
    check(parsed.recipientMmId == 'mm:bob', 'recipient binding');

    await bob.receiveEncryptedDirect(
      messageId: outer.messageId,
      fromMmId: 'mm:alice',
      encodedEnvelope: outer.payload,
    );
    final bobMessages = await bob.messagesFor('mm:alice');
    check(bobMessages.length == 1, 'bob stores one decrypted message');
    check(bobMessages.single.text == secret, 'bob plaintext restored after M07');

    var wrongRecipientRejected = false;
    try {
      await mallory.receiveEncryptedDirect(
        messageId: outer.messageId,
        fromMmId: 'mm:alice',
        encodedEnvelope: outer.payload,
      );
    } catch (_) {
      wrongRecipientRejected = true;
    }
    check(wrongRecipientRejected, 'wrong recipient must fail closed');

    var plaintextRejected = false;
    try {
      await bob.receiveText(
        messageId: 'legacy-plaintext',
        fromMmId: 'mm:alice',
        text: secret,
      );
    } catch (_) {
      plaintextRejected = true;
    }
    check(plaintextRejected, 'release policy must reject private plaintext ingress');

    final group = GroupDefinition(
      groupId: 'g1',
      displayName: 'Private Group',
      creatorMmId: 'mm:alice',
      memberMmIds: const <String>['mm:alice', 'mm:bob'],
      revision: 1,
      createdAt: DateTime.utc(2026, 9, 28),
      updatedAt: DateTime.utc(2026, 9, 28),
    );
    await aliceStorage.saveGroup(group);
    await bobStorage.saveGroup(group);

    final beforeGroupEncrypts = aliceProvider.encryptCalls;
    final groupLegs = await alice.sendGroupText(
      groupId: 'g1',
      text: 'group secret',
    );
    check(groupLegs.length == 1, 'one remote member -> one encrypted leg');
    check(
      aliceProvider.encryptCalls == beforeGroupEncrypts + 1,
      'private group fanout encrypts once per recipient leg',
    );
    check(groupLegs.single.messageClass == m07DirectEnvelopeClass,
        'group leg must carry M07 envelope');
    check(!groupLegs.single.payload.contains('group secret'),
        'group transport payload must not contain plaintext');

    await bob.receiveEncryptedGroup(
      messageId: groupLegs.single.messageId,
      fromMmId: 'mm:alice',
      groupId: 'g1',
      membershipRevision: 1,
      encodedEnvelope: groupLegs.single.payload,
    );
    final groupMessages = await bob.messagesForConversation(
      const ConversationRef.group('g1'),
    );
    check(groupMessages.length == 1, 'group decrypt/store exactly once');
    check(groupMessages.single.text == 'group secret', 'group plaintext restored');

    final noProvider = MeshMessengerCore(
      ownMmId: 'mm:blocked',
      storage: AppStorage(Directory.systemTemp.createTempSync('m07-blocked-')),
      transports: const <MessageTransport>[],
      requirePrivateE2ee: true,
    );
    var providerRequired = false;
    try {
      await noProvider.sendText(peerMmId: 'mm:bob', text: 'must not leak');
    } catch (_) {
      providerRequired = true;
    }
    check(providerRequired, 'release private send must fail without M07 provider');
    await noProvider.close();

    await alice.close();
    await bob.close();
    await mallory.close();
    print('M07_PRIVATE_PIPELINE_PASS');
  } finally {
    if (aliceRoot.existsSync()) aliceRoot.deleteSync(recursive: true);
    if (bobRoot.existsSync()) bobRoot.deleteSync(recursive: true);
    if (malloryRoot.existsSync()) malloryRoot.deleteSync(recursive: true);
  }
}
