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
  final List<DeliveryEnvelope> sent = <DeliveryEnvelope>[];
  @override String get id => 'capture';
  @override bool get isAvailable => true;
  @override Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    sent.add(envelope);
    return const TransportSendResult(TransportSendStatus.accepted);
  }
}

final class _AtomicTestProvider implements M07AtomicCryptoProvider {
  _AtomicTestProvider(this.mmId);
  final String mmId;
  final List<M07AtomicOutboundCommit> outbound = <M07AtomicOutboundCommit>[];
  final List<M07AtomicInboundCommit> inbound = <M07AtomicInboundCommit>[];
  int atomicEncryptCalls = 0;
  int legacyEncryptCalls = 0;
  int sequence = 0;

  @override
  M07SuiteProfile get suiteProfile => M07SuiteProfile(
    identityAuthSuite: 'test-id',
    handshakeSuite: 'test-handshake',
    ratchetSuite: 'test-ratchet',
    attachmentSuite: 'test-attachment',
    transportPrivacySuite: 'test-route',
  );

  @override
  Future<IdentityPublicMaterial> localIdentity() async => IdentityPublicMaterial(
    formatVersion: 1,
    mmId: mmId,
    fingerprint: 'fp-$mmId',
    identityPublicKey: 'pk-$mmId',
  );

  @override
  Future<PortablePreKeyBundle> localPreKeyBundle() async => PortablePreKeyBundle(
    formatVersion: 1,
    bundleId: 'bundle-$mmId',
    mmId: mmId,
    deviceId: 'device',
    epoch: 1,
    identityPublicKey: 'pk-$mmId',
    signedPreKeyId: 'spk',
    signedPreKeyPublic: 'spk-$mmId',
    signedPreKeySignature: 'sig-$mmId',
    expiresAtEpochMs: DateTime.utc(2030).millisecondsSinceEpoch,
    suiteProfile: suiteProfile,
  );

  @override Future<void> importPeerPreKeyBundle(PortablePreKeyBundle bundle) async {}

  @override
  bool verifyIdentityBinding(IdentityPublicMaterial identity) =>
      identity.identityPublicKey == 'pk-${identity.mmId}' &&
      identity.fingerprint == 'fp-${identity.mmId}';

  @override
  Future<SecureSessionRef> ensureDirectSession(
    IdentityPublicMaterial peer, {
    PortablePreKeyBundle? preKeyBundle,
  }) async => SecureSessionRef(
    sessionId: 'session:${peer.mmId}',
    peerMmId: peer.mmId,
    suiteId: suiteProfile.ratchetSuite,
  );

  @override
  Future<EncryptedApplicationEnvelope> encryptDirect(DirectPlaintext plaintext) async {
    legacyEncryptCalls += 1;
    throw StateError('legacy encrypt must not be used by atomic path');
  }

  @override
  Future<DirectDecryptResult> decryptDirect(
    EncryptedApplicationEnvelope envelope, {
    required String expectedLogicalMessageId,
    required String expectedSenderMmId,
    required String expectedRecipientMmId,
  }) async => const DirectDecryptRejected('legacy decrypt must not be used');

  @override
  Future<M07AtomicOutboundCommit> encryptDirectAtomic({
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
    required DirectPlaintext plaintext,
    required String recoveryContextJson,
  }) async {
    atomicEncryptCalls += 1;
    final packed = base64UrlEncode(utf8.encode(jsonEncode(<String, Object?>{
      'logicalMessageId': plaintext.logicalMessageId,
      'senderMmId': plaintext.senderMmId,
      'recipientMmId': plaintext.recipientMmId,
      'conversationKey': plaintext.conversationKey,
      'messageClass': plaintext.messageClass,
      'payloadUtf8': plaintext.payloadUtf8,
    })));
    final commit = M07AtomicOutboundCommit(
      commitId: 'out-${++sequence}',
      envelope: EncryptedApplicationEnvelope(
        formatVersion: 1,
        suiteId: suiteProfile.ratchetSuite,
        ciphertextBase64: packed,
      ),
      recoveryContextJson: recoveryContextJson,
    );
    outbound.add(commit);
    return commit;
  }

  @override
  Future<List<M07AtomicOutboundCommit>> pendingOutboundCommits() async =>
      List<M07AtomicOutboundCommit>.unmodifiable(outbound);

  @override
  Future<void> markOutboundCommitPersisted(String commitId) async {
    outbound.removeWhere((item) => item.commitId == commitId);
  }

  @override
  Future<M07AtomicDecryptOutcome> decryptDirectAtomic({
    required IdentityPublicMaterial peer,
    required EncryptedApplicationEnvelope envelope,
    required String expectedLogicalMessageId,
    required String expectedSenderMmId,
    required String expectedRecipientMmId,
    required String recoveryContextJson,
  }) async {
    final raw = jsonDecode(utf8.decode(base64Url.decode(envelope.ciphertextBase64)));
    if (raw is! Map) {
      return const M07AtomicDecryptRejected(DirectDecryptRejected('invalid'));
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['logicalMessageId'] != expectedLogicalMessageId ||
        map['senderMmId'] != expectedSenderMmId ||
        map['recipientMmId'] != expectedRecipientMmId) {
      return const M07AtomicDecryptRejected(DirectDecryptRejected('binding'));
    }
    final commit = M07AtomicInboundCommit(
      commitId: 'in-${++sequence}',
      plaintext: DirectPlaintext(
        logicalMessageId: map['logicalMessageId'] as String,
        senderMmId: map['senderMmId'] as String,
        recipientMmId: map['recipientMmId'] as String,
        conversationKey: map['conversationKey'] as String,
        messageClass: map['messageClass'] as String,
        payloadUtf8: map['payloadUtf8'] as String,
      ),
      recoveryContextJson: recoveryContextJson,
    );
    inbound.add(commit);
    return commit;
  }

  @override
  Future<List<M07AtomicInboundCommit>> pendingInboundCommits() async =>
      List<M07AtomicInboundCommit>.unmodifiable(inbound);

  @override
  Future<void> markInboundCommitPersisted(String commitId) async {
    inbound.removeWhere((item) => item.commitId == commitId);
  }

  @override
  Future<AttachmentCryptoRef> createAttachmentCrypto(
    SecureSessionRef session,
    AttachmentManifest manifest,
  ) async => AttachmentCryptoRef(
    transferId: manifest.transferId,
    keyHandle: 'unused',
    encryptedManifestBase64: 'unused',
  );

  @override
  Future<Uint8List> encryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List plaintext,
  ) async => Uint8List.fromList(plaintext);

  @override
  Future<Uint8List> decryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List ciphertext,
  ) async => Uint8List.fromList(ciphertext);
}

Contact _contact(String mmId) => Contact(
  mmId: mmId,
  displayName: mmId,
  verified: true,
  identityPublicKey: 'pk-$mmId',
  fingerprint: 'fp-$mmId',
);

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('m07-atomic-');
  try {
    final storage = AppStorage(root);
    await storage.saveContact(_contact('mm:bob'));
    final provider = _AtomicTestProvider('mm:alice');
    final transport = _CaptureTransport();
    final core = MeshMessengerCore(
      ownMmId: 'mm:alice',
      storage: storage,
      transports: <MessageTransport>[transport],
      cryptoProvider: provider,
      requirePrivateE2ee: true,
      now: () => DateTime.utc(2026, 9, 29, 2, 0),
    );
    await core.restore();

    final sent = await core.sendText(peerMmId: 'mm:bob', text: 'secret');
    check(provider.atomicEncryptCalls == 1, 'atomic encrypt must run once');
    check(provider.legacyEncryptCalls == 0, 'legacy encrypt must not run');
    check(provider.outbound.isEmpty, 'successful outbox persist must clear journal');
    check(transport.sent.single.payload == sent.payload, 'transport must reuse committed ciphertext');

    const crashMessageId = 'm-crash-out';
    provider.outbound.add(M07AtomicOutboundCommit(
      commitId: 'out-crash',
      envelope: EncryptedApplicationEnvelope(
        formatVersion: 1,
        suiteId: 'test-ratchet',
        ciphertextBase64: base64UrlEncode(utf8.encode('opaque')),
      ),
      recoveryContextJson: jsonEncode(<String, Object?>{
        'kind': 'direct_text_out',
        'messageId': crashMessageId,
        'peerMmId': 'mm:bob',
        'text': 'recovered outbound',
        'createdAt': DateTime.utc(2026, 9, 29, 2, 1).toIso8601String(),
      }),
    ));

    final recovered = MeshMessengerCore(
      ownMmId: 'mm:alice',
      storage: storage,
      transports: const <MessageTransport>[],
      cryptoProvider: provider,
      requirePrivateE2ee: true,
      now: () => DateTime.utc(2026, 9, 29, 2, 2),
    );
    await recovered.restore();
    check(recovered.deliveryById(crashMessageId) != null, 'pending ciphertext must recover into M02 outbox');
    check(provider.outbound.isEmpty, 'recovered outbound journal must be acknowledged');
    final outboundMessages = await recovered.messagesFor('mm:bob');
    check(
      outboundMessages.any((m) => m.messageId == crashMessageId && m.text == 'recovered outbound'),
      'outbound UI record must recover without re-encrypting',
    );

    provider.inbound.add(M07AtomicInboundCommit(
      commitId: 'in-crash',
      plaintext: DirectPlaintext(
        logicalMessageId: 'm-crash-in',
        senderMmId: 'mm:bob',
        recipientMmId: 'mm:alice',
        conversationKey: m07DirectSecurityContext('mm:alice', 'mm:bob'),
        messageClass: 'text',
        payloadUtf8: 'recovered inbound',
      ),
      recoveryContextJson: jsonEncode(<String, Object?>{
        'kind': 'direct_in',
        'messageId': 'm-crash-in',
        'fromMmId': 'mm:bob',
      }),
    ));
    await recovered.restore();
    check(provider.inbound.isEmpty, 'recovered inbound journal must be acknowledged');
    final inboundMessages = await recovered.messagesFor('mm:bob');
    check(
      inboundMessages.any((m) => m.messageId == 'm-crash-in' && !m.outgoing && m.text == 'recovered inbound'),
      'inbound plaintext must recover after provider ratchet commit',
    );

    await core.close();
    await recovered.close();
    print('M07_ATOMIC_RECOVERY_PASS');
  } finally {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
