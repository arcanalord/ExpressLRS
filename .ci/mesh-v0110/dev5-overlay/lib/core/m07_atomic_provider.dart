import 'dart:convert';
import 'dart:typed_data';

import 'm07_provider_state_store.dart';
import 'm07_security.dart';

/// Pure snapshot transition returned by a concrete direct-ratchet engine.
///
/// A production vodozemac bridge should deserialize [nextProviderOpaqueJson]
/// only from its own opaque provider schema. M07/M02/M12 never inspect it.
final class M07EngineEncryptTransition {
  const M07EngineEncryptTransition({
    required this.nextProviderOpaqueJson,
    required this.envelope,
  });

  final String nextProviderOpaqueJson;
  final EncryptedApplicationEnvelope envelope;
}

sealed class M07EngineDecryptTransition {
  const M07EngineDecryptTransition();
}

final class M07EngineDecryptRejected extends M07EngineDecryptTransition {
  const M07EngineDecryptRejected(this.reason);
  final String reason;
}

final class M07EngineDecryptSuccess extends M07EngineDecryptTransition {
  const M07EngineDecryptSuccess({
    required this.nextProviderOpaqueJson,
    required this.plaintext,
  });

  final String nextProviderOpaqueJson;
  final DirectPlaintext plaintext;
}


final class M07EngineStateTransition<T> {
  const M07EngineStateTransition({
    required this.nextProviderOpaqueJson,
    required this.value,
  });

  final String nextProviderOpaqueJson;
  final T value;
}

/// Snapshot-oriented engine port for a maintained crypto implementation.
///
/// The key property is that encrypt/decrypt are pure state transitions:
/// current opaque snapshot -> next opaque snapshot + result. The engine must
/// not publish a mutated global ratchet before M07ProviderStateStore commits
/// the returned snapshot and recovery journal atomically.
abstract interface class M07DirectRatchetEngine {
  M07SuiteProfile get suiteProfile;

  Future<String> createInitialProviderState({
    required String localMmId,
  });

  IdentityPublicMaterial localIdentityFromState(
    String providerOpaqueJson,
  );

  Future<M07EngineStateTransition<PortablePreKeyBundle>>
      localPreKeyBundleFromState(
    String providerOpaqueJson,
  );

  Future<M07EngineStateTransition<void>> importPeerPreKeyBundle({
    required String providerOpaqueJson,
    required PortablePreKeyBundle bundle,
  });

  bool verifyIdentityBinding(IdentityPublicMaterial identity);

  Future<M07EngineStateTransition<SecureSessionRef>> ensureDirectSession({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
  });

  Future<M07EngineEncryptTransition> encryptDirect({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
    required DirectPlaintext plaintext,
  });

  Future<M07EngineDecryptTransition> decryptDirect({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    required EncryptedApplicationEnvelope envelope,
    required String expectedLogicalMessageId,
    required String expectedSenderMmId,
    required String expectedRecipientMmId,
  });

  Future<AttachmentCryptoRef> createAttachmentCrypto({
    required String providerOpaqueJson,
    required SecureSessionRef session,
    required AttachmentManifest manifest,
  });

  Future<Uint8List> encryptAttachmentChunk({
    required String providerOpaqueJson,
    required AttachmentCryptoRef attachment,
    required int chunkIndex,
    required Uint8List plaintext,
  });

  Future<Uint8List> decryptAttachmentChunk({
    required String providerOpaqueJson,
    required AttachmentCryptoRef attachment,
    required int chunkIndex,
    required Uint8List ciphertext,
  });
}

/// Production-shaped M07 provider implementation.
///
/// It owns no transport state. Every state-changing direct crypto operation is
/// committed through one encrypted provider-state transaction before the
/// resulting ciphertext/plaintext is exposed to the application.
final class M07AtomicProvider implements M07AtomicCryptoProvider {
  M07AtomicProvider({
    required this.localMmId,
    required M07DirectRatchetEngine engine,
    required M07ProviderStateStore store,
  })  : _engine = engine,
        _store = store;

  final String localMmId;
  final M07DirectRatchetEngine _engine;
  final M07ProviderStateStore _store;
  int _commitCounter = 0;

  @override
  M07SuiteProfile get suiteProfile => _engine.suiteProfile;

  Future<M07ProviderStateSnapshot> _state() async {
    var current = await _store.load();
    if (current.providerOpaqueJson.isNotEmpty) return current;
    final initial = await _engine.createInitialProviderState(
      localMmId: localMmId,
    );
    await _store.transaction<void>((snapshot) async {
      if (snapshot.providerOpaqueJson.isNotEmpty) {
        return M07ProviderTransactionResult<void>.readOnly(
          current: snapshot,
          value: null,
        );
      }
      return M07ProviderTransactionResult<void>(
        next: snapshot.next(providerOpaqueJson: initial),
        value: null,
      );
    });
    current = await _store.load();
    if (current.providerOpaqueJson.isEmpty) {
      throw StateError('M07_PROVIDER_STATE_INIT_FAILED');
    }
    return current;
  }

  @override
  Future<IdentityPublicMaterial> localIdentity() async =>
      _engine.localIdentityFromState((await _state()).providerOpaqueJson);

  @override
  Future<PortablePreKeyBundle> localPreKeyBundle() =>
      _store.transaction<PortablePreKeyBundle>((current) async {
        final opaque = current.providerOpaqueJson.isEmpty
            ? await _engine.createInitialProviderState(localMmId: localMmId)
            : current.providerOpaqueJson;
        final transition = await _engine.localPreKeyBundleFromState(opaque);
        return M07ProviderTransactionResult<PortablePreKeyBundle>(
          next: current.next(
            providerOpaqueJson: transition.nextProviderOpaqueJson,
          ),
          value: transition.value,
        );
      });

  @override
  Future<void> importPeerPreKeyBundle(PortablePreKeyBundle bundle) async {
    await _store.transaction<void>((current) async {
      final opaque = current.providerOpaqueJson.isEmpty
          ? await _engine.createInitialProviderState(localMmId: localMmId)
          : current.providerOpaqueJson;
      final transition = await _engine.importPeerPreKeyBundle(
        providerOpaqueJson: opaque,
        bundle: bundle,
      );
      return M07ProviderTransactionResult<void>(
        next: current.next(
          providerOpaqueJson: transition.nextProviderOpaqueJson,
        ),
        value: transition.value,
      );
    });
  }

  @override
  bool verifyIdentityBinding(IdentityPublicMaterial identity) =>
      _engine.verifyIdentityBinding(identity);

  @override
  Future<SecureSessionRef> ensureDirectSession(
    IdentityPublicMaterial peer, {
    PortablePreKeyBundle? preKeyBundle,
  }) =>
      _store.transaction<SecureSessionRef>((current) async {
        final opaque = current.providerOpaqueJson.isEmpty
            ? await _engine.createInitialProviderState(localMmId: localMmId)
            : current.providerOpaqueJson;
        final transition = await _engine.ensureDirectSession(
          providerOpaqueJson: opaque,
          peer: peer,
          preKeyBundle: preKeyBundle,
        );
        return M07ProviderTransactionResult<SecureSessionRef>(
          next: current.next(
            providerOpaqueJson: transition.nextProviderOpaqueJson,
          ),
          value: transition.value,
        );
      });

  @override
  Future<EncryptedApplicationEnvelope> encryptDirect(
    DirectPlaintext plaintext,
  ) async {
    throw StateError('M07_ATOMIC_ENCRYPT_REQUIRED');
  }

  @override
  Future<DirectDecryptResult> decryptDirect(
    EncryptedApplicationEnvelope envelope, {
    required String expectedLogicalMessageId,
    required String expectedSenderMmId,
    required String expectedRecipientMmId,
  }) async {
    return const DirectDecryptRejected('M07_ATOMIC_DECRYPT_REQUIRED');
  }

  @override
  Future<M07AtomicOutboundCommit> encryptDirectAtomic({
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
    required DirectPlaintext plaintext,
    required String recoveryContextJson,
  }) =>
      _store.transaction<M07AtomicOutboundCommit>((current) async {
        final opaque = current.providerOpaqueJson.isEmpty
            ? await _engine.createInitialProviderState(localMmId: localMmId)
            : current.providerOpaqueJson;
        final transition = await _engine.encryptDirect(
          providerOpaqueJson: opaque,
          peer: peer,
          preKeyBundle: preKeyBundle,
          plaintext: plaintext,
        );
        final commit = M07AtomicOutboundCommit(
          commitId: _newCommitId('out', plaintext.logicalMessageId),
          envelope: transition.envelope,
          recoveryContextJson: recoveryContextJson,
        );
        return M07ProviderTransactionResult<M07AtomicOutboundCommit>(
          next: current.next(
            providerOpaqueJson: transition.nextProviderOpaqueJson,
            outboundCommits: <M07AtomicOutboundCommit>[
              ...current.outboundCommits,
              commit,
            ],
          ),
          value: commit,
        );
      });

  @override
  Future<List<M07AtomicOutboundCommit>> pendingOutboundCommits() async =>
      (await _state()).outboundCommits;

  @override
  Future<void> markOutboundCommitPersisted(String commitId) async {
    await _store.transaction<void>((current) async {
      final nextCommits = current.outboundCommits
          .where((item) => item.commitId != commitId)
          .toList(growable: false);
      if (nextCommits.length == current.outboundCommits.length) {
        throw StateError('M07_OUTBOUND_COMMIT_NOT_FOUND');
      }
      return M07ProviderTransactionResult<void>(
        next: current.next(outboundCommits: nextCommits),
        value: null,
      );
    });
  }

  @override
  Future<M07AtomicDecryptOutcome> decryptDirectAtomic({
    required IdentityPublicMaterial peer,
    required EncryptedApplicationEnvelope envelope,
    required String expectedLogicalMessageId,
    required String expectedSenderMmId,
    required String expectedRecipientMmId,
    required String recoveryContextJson,
  }) =>
      _store.transaction<M07AtomicDecryptOutcome>((current) async {
        final opaque = current.providerOpaqueJson.isEmpty
            ? await _engine.createInitialProviderState(localMmId: localMmId)
            : current.providerOpaqueJson;
        final transition = await _engine.decryptDirect(
          providerOpaqueJson: opaque,
          peer: peer,
          envelope: envelope,
          expectedLogicalMessageId: expectedLogicalMessageId,
          expectedSenderMmId: expectedSenderMmId,
          expectedRecipientMmId: expectedRecipientMmId,
        );
        if (transition is M07EngineDecryptRejected) {
          return M07ProviderTransactionResult<M07AtomicDecryptOutcome>.readOnly(
            current: current,
            value: M07AtomicDecryptRejected(
              DirectDecryptRejected(transition.reason),
            ),
          );
        }
        final success = transition as M07EngineDecryptSuccess;
        final commit = M07AtomicInboundCommit(
          commitId: _newCommitId('in', expectedLogicalMessageId),
          plaintext: success.plaintext,
          recoveryContextJson: recoveryContextJson,
        );
        return M07ProviderTransactionResult<M07AtomicDecryptOutcome>(
          next: current.next(
            providerOpaqueJson: success.nextProviderOpaqueJson,
            inboundCommits: <M07AtomicInboundCommit>[
              ...current.inboundCommits,
              commit,
            ],
          ),
          value: commit,
        );
      });

  @override
  Future<List<M07AtomicInboundCommit>> pendingInboundCommits() async =>
      (await _state()).inboundCommits;

  @override
  Future<void> markInboundCommitPersisted(String commitId) async {
    await _store.transaction<void>((current) async {
      final nextCommits = current.inboundCommits
          .where((item) => item.commitId != commitId)
          .toList(growable: false);
      if (nextCommits.length == current.inboundCommits.length) {
        throw StateError('M07_INBOUND_COMMIT_NOT_FOUND');
      }
      return M07ProviderTransactionResult<void>(
        next: current.next(inboundCommits: nextCommits),
        value: null,
      );
    });
  }

  @override
  Future<AttachmentCryptoRef> createAttachmentCrypto(
    SecureSessionRef session,
    AttachmentManifest manifest,
  ) async => _engine.createAttachmentCrypto(
    providerOpaqueJson: (await _state()).providerOpaqueJson,
    session: session,
    manifest: manifest,
  );

  @override
  Future<Uint8List> encryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List plaintext,
  ) async => _engine.encryptAttachmentChunk(
    providerOpaqueJson: (await _state()).providerOpaqueJson,
    attachment: attachment,
    chunkIndex: chunkIndex,
    plaintext: plaintext,
  );

  @override
  Future<Uint8List> decryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List ciphertext,
  ) async => _engine.decryptAttachmentChunk(
    providerOpaqueJson: (await _state()).providerOpaqueJson,
    attachment: attachment,
    chunkIndex: chunkIndex,
    ciphertext: ciphertext,
  );

  String _newCommitId(String direction, String messageId) {
    final serial = ++_commitCounter;
    final encoded = base64Url.encode(utf8.encode('$direction:$messageId:$serial'));
    return 'm07c-$encoded';
  }
}
