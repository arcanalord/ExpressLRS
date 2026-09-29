import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_storage_crypto.dart';
import 'm07_security.dart';

const _providerStateSchema = 'mesh-messenger-m07-provider-state/v1';
const _providerStatePurpose = 'm07-provider-state-v1';

final class M07ProviderStateSnapshot {
  const M07ProviderStateSnapshot({
    required this.generation,
    required this.providerOpaqueJson,
    required this.outboundCommits,
    required this.inboundCommits,
  });

  factory M07ProviderStateSnapshot.empty() => const M07ProviderStateSnapshot(
    generation: 0,
    providerOpaqueJson: '',
    outboundCommits: <M07AtomicOutboundCommit>[],
    inboundCommits: <M07AtomicInboundCommit>[],
  );

  final int generation;
  final String providerOpaqueJson;
  final List<M07AtomicOutboundCommit> outboundCommits;
  final List<M07AtomicInboundCommit> inboundCommits;

  M07ProviderStateSnapshot next({
    String? providerOpaqueJson,
    List<M07AtomicOutboundCommit>? outboundCommits,
    List<M07AtomicInboundCommit>? inboundCommits,
  }) => M07ProviderStateSnapshot(
    generation: generation + 1,
    providerOpaqueJson: providerOpaqueJson ?? this.providerOpaqueJson,
    outboundCommits: List.unmodifiable(
      outboundCommits ?? this.outboundCommits,
    ),
    inboundCommits: List.unmodifiable(
      inboundCommits ?? this.inboundCommits,
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'generation': generation,
    'providerOpaqueJson': providerOpaqueJson,
    'outboundCommits': outboundCommits.map(_outboundToJson).toList(),
    'inboundCommits': inboundCommits.map(_inboundToJson).toList(),
  };

  factory M07ProviderStateSnapshot.fromJson(Map<String, dynamic> json) {
    final generation = (json['generation'] as num?)?.toInt() ?? 0;
    final providerOpaqueJson = json['providerOpaqueJson'] as String? ?? '';
    final outbound = (json['outboundCommits'] as List? ?? const <Object?>[])
        .map((value) => _outboundFromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList(growable: false);
    final inbound = (json['inboundCommits'] as List? ?? const <Object?>[])
        .map((value) => _inboundFromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList(growable: false);
    return M07ProviderStateSnapshot(
      generation: generation,
      providerOpaqueJson: providerOpaqueJson,
      outboundCommits: List.unmodifiable(outbound),
      inboundCommits: List.unmodifiable(inbound),
    );
  }
}

final class M07ProviderTransactionResult<T> {
  const M07ProviderTransactionResult({
    required this.next,
    required this.value,
    this.persist = true,
  });

  const M07ProviderTransactionResult.readOnly({
    required M07ProviderStateSnapshot current,
    required this.value,
  })  : next = current,
        persist = false;

  final M07ProviderStateSnapshot next;
  final T value;
  final bool persist;
}

/// One encrypted, crash-recoverable provider state file.
///
/// The entire provider state and recovery journal are protected by
/// [AppStorageCrypto] and replaced atomically. This lets an M07 provider commit
/// ratchet/account changes together with the exact immutable ciphertext or
/// recovered plaintext needed to finish app-level persistence after a crash.
final class M07ProviderStateStore {
  M07ProviderStateStore({
    required Directory root,
    required AppStorageCrypto crypto,
  })  : _root = root,
        _crypto = crypto;

  final Directory _root;
  final AppStorageCrypto _crypto;
  Future<void> _mutationTail = Future<void>.value();

  File get _stateFile => File('${_root.path}/m07_provider_state.json');

  Future<M07ProviderStateSnapshot> load() => _serialized(_loadUnlocked);

  Future<T> transaction<T>(
    Future<M07ProviderTransactionResult<T>> Function(
      M07ProviderStateSnapshot current,
    ) mutate,
  ) => _serialized(() async {
    final current = await _loadUnlocked();
    final result = await mutate(current);
    if (!result.persist) {
      if (result.next.generation != current.generation) {
        throw StateError('M07_PROVIDER_STATE_READONLY_MUTATED');
      }
      return result.value;
    }
    if (result.next.generation <= current.generation) {
      throw StateError('M07_PROVIDER_STATE_GENERATION_NOT_ADVANCED');
    }
    await _writeUnlocked(result.next);
    return result.value;
  });

  Future<M07ProviderStateSnapshot> _loadUnlocked() async {
    final main = _stateFile;
    final backup = File('${main.path}.bak');
    final candidates = <File>[
      if (await main.exists()) main,
      if (await backup.exists()) backup,
    ];
    if (candidates.isEmpty) return M07ProviderStateSnapshot.empty();

    Object? lastError;
    for (final file in candidates) {
      try {
        final snapshot = await _decodeEncrypted(await file.readAsString());
        if (file.path == backup.path) {
          await _writeUnlocked(snapshot.next(
            providerOpaqueJson: snapshot.providerOpaqueJson,
            outboundCommits: snapshot.outboundCommits,
            inboundCommits: snapshot.inboundCommits,
          ));
          return (await _decodeEncrypted(await main.readAsString()));
        }
        return snapshot;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('M07_PROVIDER_STATE_UNREADABLE:$lastError');
  }

  Future<M07ProviderStateSnapshot> _decodeEncrypted(String diskText) async {
    final raw = jsonDecode(diskText);
    if (raw is! Map) {
      throw const FormatException('M07_PROVIDER_STATE_ENVELOPE_INVALID');
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['schema'] != _providerStateSchema ||
        map['purpose'] != _providerStatePurpose) {
      throw const FormatException('M07_PROVIDER_STATE_SCHEMA_INVALID');
    }
    final iv = map['iv'] as String? ?? '';
    final ciphertext = map['ciphertext'] as String? ?? '';
    if (iv.isEmpty || ciphertext.isEmpty) {
      throw const FormatException('M07_PROVIDER_STATE_CIPHERTEXT_MISSING');
    }
    final plaintext = await _crypto.decrypt(
      purpose: _providerStatePurpose,
      iv: iv,
      ciphertext: ciphertext,
    );
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map) {
      throw const FormatException('M07_PROVIDER_STATE_PAYLOAD_INVALID');
    }
    return M07ProviderStateSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<void> _writeUnlocked(M07ProviderStateSnapshot snapshot) async {
    await _root.create(recursive: true);
    final plaintext = jsonEncode(snapshot.toJson());
    final sealed = await _crypto.encrypt(
      purpose: _providerStatePurpose,
      plaintext: plaintext,
    );
    final iv = sealed['iv'] ?? '';
    final ciphertext = sealed['ciphertext'] ?? '';
    if (sealed['purpose'] != _providerStatePurpose ||
        iv.isEmpty ||
        ciphertext.isEmpty) {
      throw StateError('M07_PROVIDER_STATE_ENCRYPTION_INVALID');
    }
    final diskText = jsonEncode(<String, Object?>{
      'schema': _providerStateSchema,
      'purpose': _providerStatePurpose,
      'iv': iv,
      'ciphertext': ciphertext,
    });
    await _writeTextAtomically(_stateFile, diskText);
  }

  Future<void> _writeTextAtomically(File file, String text) async {
    final tmp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await tmp.writeAsString(text, flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await tmp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    })();
  }
}

Map<String, Object?> _outboundToJson(M07AtomicOutboundCommit commit) => {
  'commitId': commit.commitId,
  'envelope': commit.envelope.encode(),
  'recoveryContextJson': commit.recoveryContextJson,
};

M07AtomicOutboundCommit _outboundFromJson(Map<String, dynamic> json) =>
    M07AtomicOutboundCommit(
      commitId: json['commitId'] as String,
      envelope: EncryptedApplicationEnvelope.decode(
        json['envelope'] as String,
      ),
      recoveryContextJson: json['recoveryContextJson'] as String,
    );

Map<String, Object?> _inboundToJson(M07AtomicInboundCommit commit) => {
  'commitId': commit.commitId,
  'plaintext': <String, Object?>{
    'logicalMessageId': commit.plaintext.logicalMessageId,
    'senderMmId': commit.plaintext.senderMmId,
    'recipientMmId': commit.plaintext.recipientMmId,
    'conversationKey': commit.plaintext.conversationKey,
    'messageClass': commit.plaintext.messageClass,
    'payloadUtf8': commit.plaintext.payloadUtf8,
  },
  'recoveryContextJson': commit.recoveryContextJson,
};

M07AtomicInboundCommit _inboundFromJson(Map<String, dynamic> json) {
  final rawPlaintext = json['plaintext'];
  if (rawPlaintext is! Map) {
    throw const FormatException('M07_PROVIDER_INBOUND_PLAINTEXT_INVALID');
  }
  final plaintext = Map<String, dynamic>.from(rawPlaintext);
  return M07AtomicInboundCommit(
    commitId: json['commitId'] as String,
    plaintext: DirectPlaintext(
      logicalMessageId: plaintext['logicalMessageId'] as String,
      senderMmId: plaintext['senderMmId'] as String,
      recipientMmId: plaintext['recipientMmId'] as String,
      conversationKey: plaintext['conversationKey'] as String,
      messageClass: plaintext['messageClass'] as String,
      payloadUtf8: plaintext['payloadUtf8'] as String,
    ),
    recoveryContextJson: json['recoveryContextJson'] as String,
  );
}
