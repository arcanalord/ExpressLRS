import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/local_storage_crypto.dart';
import '../lib/core/m07_atomic_provider.dart';
import '../lib/core/m07_provider_state_store.dart';
import '../lib/core/m07_security.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final class _FakeCrypto implements AppStorageCrypto {
  @override
  Future<Map<String, String>> encrypt({
    required String purpose,
    required String plaintext,
  }) async => <String, String>{
    'purpose': purpose,
    'iv': 'iv',
    'ciphertext': base64UrlEncode(utf8.encode(plaintext)),
  };

  @override
  Future<String> decrypt({
    required String purpose,
    required String iv,
    required String ciphertext,
  }) async => utf8.decode(base64Url.decode(ciphertext));
}

final class _FakeEngine implements M07DirectRatchetEngine {
  @override
  M07SuiteProfile get suiteProfile => M07SuiteProfile(
    identityAuthSuite: 'fake-id',
    handshakeSuite: 'fake-handshake',
    ratchetSuite: 'fake-ratchet',
    attachmentSuite: 'fake-attachment',
    transportPrivacySuite: 'fake-route',
  );

  @override
  Future<String> createInitialProviderState({required String localMmId}) async =>
      jsonEncode(<String, Object?>{'localMmId': localMmId, 'counter': 0});

  @override
  IdentityPublicMaterial localIdentityFromState(String providerOpaqueJson) {
    final raw = Map<String, dynamic>.from(jsonDecode(providerOpaqueJson) as Map);
    final mmId = raw['localMmId'] as String;
    return IdentityPublicMaterial(
      formatVersion: 1,
      mmId: mmId,
      fingerprint: 'fp-' + mmId,
      identityPublicKey: 'pk-' + mmId,
    );
  }

  @override
  Future<M07EngineStateTransition<PortablePreKeyBundle>>
      localPreKeyBundleFromState(
    String providerOpaqueJson,
  ) async {
    final identity = localIdentityFromState(providerOpaqueJson);
    final raw = Map<String, dynamic>.from(jsonDecode(providerOpaqueJson) as Map);
    raw['prekeyGeneration'] = ((raw['prekeyGeneration'] as num?)?.toInt() ?? 0) + 1;
    return M07EngineStateTransition<PortablePreKeyBundle>(
      nextProviderOpaqueJson: jsonEncode(raw),
      value: PortablePreKeyBundle(
        formatVersion: 1,
        bundleId: 'bundle-' + identity.mmId,
        mmId: identity.mmId,
        deviceId: 'device',
        epoch: raw['prekeyGeneration'] as int,
        identityPublicKey: identity.identityPublicKey,
        signedPreKeyId: 'spk',
        signedPreKeyPublic: 'spk-' + identity.mmId,
        signedPreKeySignature: 'sig-' + identity.mmId,
        expiresAtEpochMs: DateTime.utc(2030).millisecondsSinceEpoch,
        suiteProfile: suiteProfile,
      ),
    );
  }

  @override
  Future<M07EngineStateTransition<void>> importPeerPreKeyBundle({
    required String providerOpaqueJson,
    required PortablePreKeyBundle bundle,
  }) async {
    final raw = Map<String, dynamic>.from(jsonDecode(providerOpaqueJson) as Map);
    raw['lastImportedPeer'] = bundle.mmId;
    return M07EngineStateTransition<void>(
      nextProviderOpaqueJson: jsonEncode(raw),
      value: null,
    );
  }

  @override
  bool verifyIdentityBinding(IdentityPublicMaterial identity) =>
      identity.identityPublicKey == 'pk-' + identity.mmId &&
      identity.fingerprint == 'fp-' + identity.mmId;

  @override
  Future<M07EngineStateTransition<SecureSessionRef>> ensureDirectSession({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
  }) async {
    final raw = Map<String, dynamic>.from(jsonDecode(providerOpaqueJson) as Map);
    raw['sessionFor'] = peer.mmId;
    return M07EngineStateTransition<SecureSessionRef>(
      nextProviderOpaqueJson: jsonEncode(raw),
      value: SecureSessionRef(
        sessionId: 's-' + peer.mmId,
        peerMmId: peer.mmId,
        suiteId: suiteProfile.ratchetSuite,
      ),
    );
  }

  @override
  Future<M07EngineEncryptTransition> encryptDirect({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
    required DirectPlaintext plaintext,
  }) async {
    final raw = Map<String, dynamic>.from(jsonDecode(providerOpaqueJson) as Map);
    raw['counter'] = (raw['counter'] as num).toInt() + 1;
    return M07EngineEncryptTransition(
      nextProviderOpaqueJson: jsonEncode(raw),
      envelope: EncryptedApplicationEnvelope(
        formatVersion: 1,
        suiteId: suiteProfile.ratchetSuite,
        ciphertextBase64: base64UrlEncode(
          utf8.encode(jsonEncode(<String, Object?>{
            'logicalMessageId': plaintext.logicalMessageId,
            'senderMmId': plaintext.senderMmId,
            'recipientMmId': plaintext.recipientMmId,
            'conversationKey': plaintext.conversationKey,
            'messageClass': plaintext.messageClass,
            'payloadUtf8': plaintext.payloadUtf8,
          })),
        ),
      ),
    );
  }

  @override
  Future<M07EngineDecryptTransition> decryptDirect({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    required EncryptedApplicationEnvelope envelope,
    required String expectedLogicalMessageId,
    required String expectedSenderMmId,
    required String expectedRecipientMmId,
  }) async {
    final map = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(base64Url.decode(envelope.ciphertextBase64))) as Map,
    );
    if (map['logicalMessageId'] != expectedLogicalMessageId ||
        map['senderMmId'] != expectedSenderMmId ||
        map['recipientMmId'] != expectedRecipientMmId) {
      return const M07EngineDecryptRejected('binding');
    }
    final raw = Map<String, dynamic>.from(jsonDecode(providerOpaqueJson) as Map);
    raw['counter'] = (raw['counter'] as num).toInt() + 1;
    return M07EngineDecryptSuccess(
      nextProviderOpaqueJson: jsonEncode(raw),
      plaintext: DirectPlaintext(
        logicalMessageId: map['logicalMessageId'] as String,
        senderMmId: map['senderMmId'] as String,
        recipientMmId: map['recipientMmId'] as String,
        conversationKey: map['conversationKey'] as String,
        messageClass: map['messageClass'] as String,
        payloadUtf8: map['payloadUtf8'] as String,
      ),
    );
  }

  @override
  Future<AttachmentCryptoRef> createAttachmentCrypto({
    required String providerOpaqueJson,
    required SecureSessionRef session,
    required AttachmentManifest manifest,
  }) async => AttachmentCryptoRef(
    transferId: manifest.transferId,
    keyHandle: 'fake',
    encryptedManifestBase64: 'fake',
  );

  @override
  Future<Uint8List> encryptAttachmentChunk({
    required String providerOpaqueJson,
    required AttachmentCryptoRef attachment,
    required int chunkIndex,
    required Uint8List plaintext,
  }) async => Uint8List.fromList(plaintext);

  @override
  Future<Uint8List> decryptAttachmentChunk({
    required String providerOpaqueJson,
    required AttachmentCryptoRef attachment,
    required int chunkIndex,
    required Uint8List ciphertext,
  }) async => Uint8List.fromList(ciphertext);
}

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('m07-provider-adapter-');
  final bobRoot = Directory.systemTemp.createTempSync('m07-provider-bob-');
  try {
    final store = M07ProviderStateStore(
      root: root,
      crypto: _FakeCrypto(),
    );
    final provider = M07AtomicProvider(
      localMmId: 'mm:alice',
      engine: _FakeEngine(),
      store: store,
    );
    final peer = IdentityPublicMaterial(
      formatVersion: 1,
      mmId: 'mm:bob',
      fingerprint: 'fp-mm:bob',
      identityPublicKey: 'pk-mm:bob',
    );
    final preKey = await provider.localPreKeyBundle();
    check(preKey.mmId == 'mm:alice', 'local prekey bundle must bind local identity');
    final afterPreKey = await store.load();
    check(
      afterPreKey.providerOpaqueJson.contains('prekeyGeneration'),
      'prekey generation state must be persisted',
    );

    final session = await provider.ensureDirectSession(peer);
    check(session.peerMmId == 'mm:bob', 'session bootstrap must return peer session');
    final afterSession = await store.load();
    check(
      afterSession.providerOpaqueJson.contains('sessionFor'),
      'session bootstrap state must be persisted',
    );

    final outbound = await provider.encryptDirectAtomic(
      peer: peer,
      plaintext: DirectPlaintext(
        logicalMessageId: 'm1',
        senderMmId: 'mm:alice',
        recipientMmId: 'mm:bob',
        conversationKey: m07DirectSecurityContext('mm:alice', 'mm:bob'),
        messageClass: 'text',
        payloadUtf8: 'hello',
      ),
      recoveryContextJson: '{"kind":"direct_text_out"}',
    );

    check((await provider.pendingOutboundCommits()).length == 1,
        'outbound commit must be durable');
    final disk = await File(root.path + '/m07_provider_state.json').readAsString();
    check(!disk.contains('hello'), 'state/journal must be encrypted at rest');
    check(!disk.contains('mm:alice'), 'identity must not leak in provider state file');

    await provider.markOutboundCommitPersisted(outbound.commitId);
    check((await provider.pendingOutboundCommits()).isEmpty,
        'outbound journal must clear after app persistence');

    final bobStore = M07ProviderStateStore(
      root: bobRoot,
      crypto: _FakeCrypto(),
    );
    final bob = M07AtomicProvider(
      localMmId: 'mm:bob',
      engine: _FakeEngine(),
      store: bobStore,
    );
    final beforeRejected = await bobStore.load();
    final rejected = await bob.decryptDirectAtomic(
      peer: IdentityPublicMaterial(
        formatVersion: 1,
        mmId: 'mm:alice',
        fingerprint: 'fp-mm:alice',
        identityPublicKey: 'pk-mm:alice',
      ),
      envelope: outbound.envelope,
      expectedLogicalMessageId: 'wrong-id',
      expectedSenderMmId: 'mm:alice',
      expectedRecipientMmId: 'mm:bob',
      recoveryContextJson: '{"kind":"direct_in"}',
    );
    check(rejected is M07AtomicDecryptRejected, 'binding mismatch must reject');
    final afterRejected = await bobStore.load();
    check(
      afterRejected.generation == beforeRejected.generation,
      'rejected decrypt must not rewrite provider state',
    );

    final inbound = await bob.decryptDirectAtomic(
      peer: IdentityPublicMaterial(
        formatVersion: 1,
        mmId: 'mm:alice',
        fingerprint: 'fp-mm:alice',
        identityPublicKey: 'pk-mm:alice',
      ),
      envelope: outbound.envelope,
      expectedLogicalMessageId: 'm1',
      expectedSenderMmId: 'mm:alice',
      expectedRecipientMmId: 'mm:bob',
      recoveryContextJson: '{"kind":"direct_in"}',
    );
    check(inbound is M07AtomicInboundCommit, 'valid ciphertext must decrypt');
    final commit = inbound as M07AtomicInboundCommit;
    check(commit.plaintext.payloadUtf8 == 'hello', 'plaintext must recover');
    check((await bob.pendingInboundCommits()).length == 1,
        'inbound commit must be durable before app storage ack');
    await bob.markInboundCommitPersisted(commit.commitId);
    check((await bob.pendingInboundCommits()).isEmpty,
        'inbound journal must clear after app storage');

    print('M07_ATOMIC_PROVIDER_ADAPTER_PASS');
  } finally {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (bobRoot.existsSync()) bobRoot.deleteSync(recursive: true);
  }
}
