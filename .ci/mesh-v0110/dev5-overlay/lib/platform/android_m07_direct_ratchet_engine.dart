import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/m07_atomic_provider.dart';
import '../core/m07_security.dart';

const _channelName = 'org.fpvclub.mesh/m07';
const _stateSchema = 'mesh-m07-vodozemac-state/v1';

/// Android bridge for the maintained vodozemac direct-ratchet engine.
///
/// This class is only the concrete M07 engine adapter. M02/M12 never call the
/// platform channel and never inspect provider state. The returned state JSON
/// is owned by this adapter/native provider and is committed atomically by
/// M07ProviderStateStore before any ciphertext leaves M07.
final class AndroidM07DirectRatchetEngine implements M07DirectRatchetEngine {
  AndroidM07DirectRatchetEngine._({
    required MethodChannel channel,
    required M07SuiteProfile suiteProfile,
    required this.providerId,
  })  : _channel = channel,
        _suiteProfile = suiteProfile;

  final MethodChannel _channel;
  final M07SuiteProfile _suiteProfile;
  final String providerId;

  static Future<AndroidM07DirectRatchetEngine?> tryCreate({
    MethodChannel? channel,
  }) async {
    final resolved = channel ?? const MethodChannel(_channelName);
    final raw = await resolved.invokeMethod<Object?>('capabilities');
    if (raw is! Map) {
      throw const FormatException('M07_NATIVE_CAPABILITIES_INVALID');
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['available'] != true) return null;
    final providerId = map['providerId'] as String? ?? '';
    final suites = map['suiteProfile'];
    if (providerId.isEmpty || suites is! Map) {
      throw const FormatException('M07_NATIVE_CAPABILITIES_INCOMPLETE');
    }
    return AndroidM07DirectRatchetEngine._(
      channel: resolved,
      suiteProfile: M07SuiteProfile.fromJson(
        Map<String, dynamic>.from(suites),
      ),
      providerId: providerId,
    );
  }

  @override
  M07SuiteProfile get suiteProfile => _suiteProfile;

  @override
  Future<String> createInitialProviderState({
    required String localMmId,
  }) async {
    final raw = await _invokeMap('createInitialState', <String, Object?>{
      'localMmId': localMmId,
    });
    return _validatedState(raw['state']);
  }

  @override
  IdentityPublicMaterial localIdentityFromState(String providerOpaqueJson) {
    final state = _decodeState(providerOpaqueJson);
    final rawIdentity = state['identity'];
    if (rawIdentity is! Map) {
      throw const FormatException('M07_NATIVE_IDENTITY_MISSING');
    }
    final identity = Map<String, dynamic>.from(rawIdentity);
    return IdentityPublicMaterial(
      formatVersion: (identity['formatVersion'] as num?)?.toInt() ?? 0,
      mmId: identity['mmId'] as String? ?? '',
      fingerprint: identity['fingerprint'] as String? ?? '',
      identityPublicKey: identity['identityPublicKey'] as String? ?? '',
      deviceId: identity['deviceId'] as String?,
      devicePublicKey: identity['devicePublicKey'] as String?,
    );
  }

  @override
  Future<M07EngineStateTransition<PortablePreKeyBundle>>
      localPreKeyBundleFromState(String providerOpaqueJson) async {
    final raw = await _invokeMap('localPreKeyBundle', <String, Object?>{
      'state': providerOpaqueJson,
    });
    final bundleRaw = raw['bundle'];
    if (bundleRaw is! String || bundleRaw.isEmpty) {
      throw const FormatException('M07_NATIVE_PREKEY_MISSING');
    }
    return M07EngineStateTransition<PortablePreKeyBundle>(
      nextProviderOpaqueJson: _validatedState(raw['nextState']),
      value: PortablePreKeyBundle.decode(bundleRaw),
    );
  }

  @override
  Future<M07EngineStateTransition<void>> importPeerPreKeyBundle({
    required String providerOpaqueJson,
    required PortablePreKeyBundle bundle,
  }) async {
    final raw = await _invokeMap('importPeerPreKeyBundle', <String, Object?>{
      'state': providerOpaqueJson,
      'bundle': bundle.encode(),
    });
    return M07EngineStateTransition<void>(
      nextProviderOpaqueJson: _validatedState(raw['nextState']),
      value: null,
    );
  }

  @override
  bool verifyIdentityBinding(IdentityPublicMaterial identity) {
    if (!identity.mmId.startsWith('mm:')) return false;
    if (identity.fingerprint.isEmpty || identity.identityPublicKey.isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Future<M07EngineStateTransition<SecureSessionRef>> ensureDirectSession({
    required String providerOpaqueJson,
    required IdentityPublicMaterial peer,
    PortablePreKeyBundle? preKeyBundle,
  }) async {
    final raw = await _invokeMap('ensureDirectSession', <String, Object?>{
      'state': providerOpaqueJson,
      'peer': _identityToJson(peer),
      if (preKeyBundle != null) 'preKeyBundle': preKeyBundle.encode(),
    });
    final sessionRaw = raw['session'];
    if (sessionRaw is! Map) {
      throw const FormatException('M07_NATIVE_SESSION_MISSING');
    }
    final session = Map<String, dynamic>.from(sessionRaw);
    return M07EngineStateTransition<SecureSessionRef>(
      nextProviderOpaqueJson: _validatedState(raw['nextState']),
      value: SecureSessionRef(
        sessionId: session['sessionId'] as String? ?? '',
        peerMmId: session['peerMmId'] as String? ?? '',
        suiteId: session['suiteId'] as String? ?? '',
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
    final raw = await _invokeMap('encryptDirect', <String, Object?>{
      'state': providerOpaqueJson,
      'peer': _identityToJson(peer),
      if (preKeyBundle != null) 'preKeyBundle': preKeyBundle.encode(),
      'plaintext': _plaintextToJson(plaintext),
    });
    final envelopeRaw = raw['envelope'];
    if (envelopeRaw is! String || envelopeRaw.isEmpty) {
      throw const FormatException('M07_NATIVE_ENVELOPE_MISSING');
    }
    return M07EngineEncryptTransition(
      nextProviderOpaqueJson: _validatedState(raw['nextState']),
      envelope: EncryptedApplicationEnvelope.decode(envelopeRaw),
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
    final raw = await _invokeMap('decryptDirect', <String, Object?>{
      'state': providerOpaqueJson,
      'peer': _identityToJson(peer),
      'envelope': envelope.encode(),
      'expectedLogicalMessageId': expectedLogicalMessageId,
      'expectedSenderMmId': expectedSenderMmId,
      'expectedRecipientMmId': expectedRecipientMmId,
    });
    if (raw['accepted'] != true) {
      return M07EngineDecryptRejected(
        raw['reason'] as String? ?? 'M07_NATIVE_DECRYPT_REJECTED',
      );
    }
    final plaintextRaw = raw['plaintext'];
    if (plaintextRaw is! Map) {
      throw const FormatException('M07_NATIVE_PLAINTEXT_MISSING');
    }
    return M07EngineDecryptSuccess(
      nextProviderOpaqueJson: _validatedState(raw['nextState']),
      plaintext: _plaintextFromJson(
        Map<String, dynamic>.from(plaintextRaw),
      ),
    );
  }

  @override
  Future<AttachmentCryptoRef> createAttachmentCrypto({
    required String providerOpaqueJson,
    required SecureSessionRef session,
    required AttachmentManifest manifest,
  }) async {
    final raw = await _invokeMap('createAttachmentCrypto', <String, Object?>{
      'state': providerOpaqueJson,
      'session': <String, Object?>{
        'sessionId': session.sessionId,
        'peerMmId': session.peerMmId,
        'suiteId': session.suiteId,
      },
      'manifest': <String, Object?>{
        'transferId': manifest.transferId,
        'logicalMessageId': manifest.logicalMessageId,
        'sizeBytes': manifest.sizeBytes,
        'contentHash': manifest.contentHash,
        'mediaType': manifest.mediaType,
      },
    });
    return AttachmentCryptoRef(
      transferId: raw['transferId'] as String? ?? '',
      keyHandle: raw['keyHandle'] as String? ?? '',
      encryptedManifestBase64:
          raw['encryptedManifestBase64'] as String? ?? '',
    );
  }

  @override
  Future<Uint8List> encryptAttachmentChunk({
    required String providerOpaqueJson,
    required AttachmentCryptoRef attachment,
    required int chunkIndex,
    required Uint8List plaintext,
  }) async {
    final raw = await _invokeMap('encryptAttachmentChunk', <String, Object?>{
      'state': providerOpaqueJson,
      'attachment': _attachmentToJson(attachment),
      'chunkIndex': chunkIndex,
      'plaintextBase64': base64Encode(plaintext),
    });
    return _requiredBytes(raw['ciphertextBase64'], 'M07_NATIVE_CHUNK_CIPHERTEXT');
  }

  @override
  Future<Uint8List> decryptAttachmentChunk({
    required String providerOpaqueJson,
    required AttachmentCryptoRef attachment,
    required int chunkIndex,
    required Uint8List ciphertext,
  }) async {
    final raw = await _invokeMap('decryptAttachmentChunk', <String, Object?>{
      'state': providerOpaqueJson,
      'attachment': _attachmentToJson(attachment),
      'chunkIndex': chunkIndex,
      'ciphertextBase64': base64Encode(ciphertext),
    });
    return _requiredBytes(raw['plaintextBase64'], 'M07_NATIVE_CHUNK_PLAINTEXT');
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(method, arguments);
    if (raw is! Map) {
      throw PlatformException(
        code: 'M07_NATIVE_FORMAT',
        message: '$method result must be a map',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  String _validatedState(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      throw const FormatException('M07_NATIVE_STATE_MISSING');
    }
    _decodeState(raw);
    return raw;
  }

  Map<String, dynamic> _decodeState(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('M07_NATIVE_STATE_INVALID');
    }
    final state = Map<String, dynamic>.from(decoded);
    if (state['schema'] != _stateSchema) {
      throw const FormatException('M07_NATIVE_STATE_SCHEMA_INVALID');
    }
    return state;
  }
}

Map<String, Object?> _identityToJson(IdentityPublicMaterial value) => {
  'formatVersion': value.formatVersion,
  'mmId': value.mmId,
  'fingerprint': value.fingerprint,
  'identityPublicKey': value.identityPublicKey,
  if (value.deviceId != null) 'deviceId': value.deviceId,
  if (value.devicePublicKey != null) 'devicePublicKey': value.devicePublicKey,
};

Map<String, Object?> _plaintextToJson(DirectPlaintext value) => {
  'logicalMessageId': value.logicalMessageId,
  'senderMmId': value.senderMmId,
  'recipientMmId': value.recipientMmId,
  'conversationKey': value.conversationKey,
  'messageClass': value.messageClass,
  'payloadUtf8': value.payloadUtf8,
};

DirectPlaintext _plaintextFromJson(Map<String, dynamic> value) =>
    DirectPlaintext(
      logicalMessageId: value['logicalMessageId'] as String? ?? '',
      senderMmId: value['senderMmId'] as String? ?? '',
      recipientMmId: value['recipientMmId'] as String? ?? '',
      conversationKey: value['conversationKey'] as String? ?? '',
      messageClass: value['messageClass'] as String? ?? '',
      payloadUtf8: value['payloadUtf8'] as String? ?? '',
    );

Map<String, Object?> _attachmentToJson(AttachmentCryptoRef value) => {
  'transferId': value.transferId,
  'keyHandle': value.keyHandle,
  'encryptedManifestBase64': value.encryptedManifestBase64,
};

Uint8List _requiredBytes(Object? raw, String code) {
  if (raw is! String || raw.isEmpty) throw FormatException(code);
  return Uint8List.fromList(base64Decode(raw));
}
