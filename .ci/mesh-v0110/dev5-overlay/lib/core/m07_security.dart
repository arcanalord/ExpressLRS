import 'dart:convert';
import 'dart:typed_data';

void _require(bool condition, String message) {
  if (!condition) throw ArgumentError(message);
}

const String m07DirectEnvelopeClass = 'm07_direct';

final class M07SuiteProfile {
  M07SuiteProfile({
    required this.identityAuthSuite,
    required this.handshakeSuite,
    required this.ratchetSuite,
    required this.attachmentSuite,
    required this.transportPrivacySuite,
  }) {
    _require(identityAuthSuite.isNotEmpty, 'identityAuthSuite must not be empty');
    _require(handshakeSuite.isNotEmpty, 'handshakeSuite must not be empty');
    _require(ratchetSuite.isNotEmpty, 'ratchetSuite must not be empty');
    _require(attachmentSuite.isNotEmpty, 'attachmentSuite must not be empty');
    _require(
      transportPrivacySuite.isNotEmpty,
      'transportPrivacySuite must not be empty',
    );
  }

  final String identityAuthSuite;
  final String handshakeSuite;
  final String ratchetSuite;
  final String attachmentSuite;
  final String transportPrivacySuite;

  Map<String, Object?> toJson() => {
    'identityAuthSuite': identityAuthSuite,
    'handshakeSuite': handshakeSuite,
    'ratchetSuite': ratchetSuite,
    'attachmentSuite': attachmentSuite,
    'transportPrivacySuite': transportPrivacySuite,
  };

  factory M07SuiteProfile.fromJson(Map<String, dynamic> json) => M07SuiteProfile(
    identityAuthSuite: json['identityAuthSuite'] as String? ?? '',
    handshakeSuite: json['handshakeSuite'] as String? ?? '',
    ratchetSuite: json['ratchetSuite'] as String? ?? '',
    attachmentSuite: json['attachmentSuite'] as String? ?? '',
    transportPrivacySuite: json['transportPrivacySuite'] as String? ?? '',
  );
}

/// Provider-portable asynchronous session bootstrap material.
///
/// M07 validates only the durable shape here. Signature verification, suite
/// compatibility, one-time-prekey consumption and rollback protection belong
/// to the maintained crypto provider.
final class PortablePreKeyBundle {
  PortablePreKeyBundle({
    required this.formatVersion,
    required this.bundleId,
    required this.mmId,
    required this.deviceId,
    required this.epoch,
    required this.identityPublicKey,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    required this.expiresAtEpochMs,
    required this.suiteProfile,
    this.oneTimePreKeyId,
    this.oneTimePreKeyPublic,
    this.pqPreKeyId,
    this.pqPreKeyPublic,
    this.pqPreKeySignature,
  }) {
    _require(formatVersion > 0, 'formatVersion must be positive');
    _require(bundleId.isNotEmpty, 'bundleId must not be empty');
    _require(mmId.startsWith('mm:'), 'mmId must start with mm:');
    _require(deviceId.isNotEmpty, 'deviceId must not be empty');
    _require(epoch >= 0, 'epoch must not be negative');
    _require(identityPublicKey.isNotEmpty, 'identityPublicKey must not be empty');
    _require(signedPreKeyId.isNotEmpty, 'signedPreKeyId must not be empty');
    _require(signedPreKeyPublic.isNotEmpty, 'signedPreKeyPublic must not be empty');
    _require(
      signedPreKeySignature.isNotEmpty,
      'signedPreKeySignature must not be empty',
    );
    _require(expiresAtEpochMs > 0, 'expiresAtEpochMs must be positive');
    _require(
      (oneTimePreKeyId == null) == (oneTimePreKeyPublic == null),
      'one-time prekey id/public must appear together',
    );
    final pqCount = [
      pqPreKeyId,
      pqPreKeyPublic,
      pqPreKeySignature,
    ].where((value) => value != null).length;
    _require(pqCount == 0 || pqCount == 3, 'PQ prekey fields must appear together');
  }

  final int formatVersion;
  final String bundleId;
  final String mmId;
  final String deviceId;
  final int epoch;
  final String identityPublicKey;
  final String signedPreKeyId;
  final String signedPreKeyPublic;
  final String signedPreKeySignature;
  final String? oneTimePreKeyId;
  final String? oneTimePreKeyPublic;
  final String? pqPreKeyId;
  final String? pqPreKeyPublic;
  final String? pqPreKeySignature;
  final int expiresAtEpochMs;
  final M07SuiteProfile suiteProfile;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'bundleId': bundleId,
    'mmId': mmId,
    'deviceId': deviceId,
    'epoch': epoch,
    'identityPublicKey': identityPublicKey,
    'signedPreKeyId': signedPreKeyId,
    'signedPreKeyPublic': signedPreKeyPublic,
    'signedPreKeySignature': signedPreKeySignature,
    if (oneTimePreKeyId != null) 'oneTimePreKeyId': oneTimePreKeyId,
    if (oneTimePreKeyPublic != null) 'oneTimePreKeyPublic': oneTimePreKeyPublic,
    if (pqPreKeyId != null) 'pqPreKeyId': pqPreKeyId,
    if (pqPreKeyPublic != null) 'pqPreKeyPublic': pqPreKeyPublic,
    if (pqPreKeySignature != null) 'pqPreKeySignature': pqPreKeySignature,
    'expiresAtEpochMs': expiresAtEpochMs,
    'suiteProfile': suiteProfile.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory PortablePreKeyBundle.fromJson(Map<String, dynamic> json) {
    final suites = json['suiteProfile'];
    if (suites is! Map) throw const FormatException('M07_PREKEY_SUITES_INVALID');
    return PortablePreKeyBundle(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
      bundleId: json['bundleId'] as String? ?? '',
      mmId: json['mmId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      epoch: (json['epoch'] as num?)?.toInt() ?? -1,
      identityPublicKey: json['identityPublicKey'] as String? ?? '',
      signedPreKeyId: json['signedPreKeyId'] as String? ?? '',
      signedPreKeyPublic: json['signedPreKeyPublic'] as String? ?? '',
      signedPreKeySignature: json['signedPreKeySignature'] as String? ?? '',
      oneTimePreKeyId: json['oneTimePreKeyId'] as String?,
      oneTimePreKeyPublic: json['oneTimePreKeyPublic'] as String?,
      pqPreKeyId: json['pqPreKeyId'] as String?,
      pqPreKeyPublic: json['pqPreKeyPublic'] as String?,
      pqPreKeySignature: json['pqPreKeySignature'] as String?,
      expiresAtEpochMs: (json['expiresAtEpochMs'] as num?)?.toInt() ?? 0,
      suiteProfile: M07SuiteProfile.fromJson(
        Map<String, dynamic>.from(suites),
      ),
    );
  }

  factory PortablePreKeyBundle.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('M07_PREKEY_INVALID');
    return PortablePreKeyBundle.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}

final class IdentityPublicMaterial {
  IdentityPublicMaterial({
    required this.formatVersion,
    required this.mmId,
    required this.fingerprint,
    required this.identityPublicKey,
    this.deviceId,
    this.devicePublicKey,
  }) {
    _require(formatVersion > 0, 'formatVersion must be positive');
    _require(mmId.startsWith('mm:'), 'mmId must start with mm:');
    _require(fingerprint.isNotEmpty, 'fingerprint must not be empty');
    _require(identityPublicKey.isNotEmpty, 'identityPublicKey must not be empty');
    _require(deviceId == null || deviceId!.isNotEmpty, 'deviceId must not be empty');
    _require(
      devicePublicKey == null || devicePublicKey!.isNotEmpty,
      'devicePublicKey must not be empty',
    );
  }

  final int formatVersion;
  final String mmId;
  final String fingerprint;
  final String identityPublicKey;
  final String? deviceId;
  final String? devicePublicKey;
}

final class SecureSessionRef {
  SecureSessionRef({
    required this.sessionId,
    required this.peerMmId,
    required this.suiteId,
  }) {
    _require(sessionId.isNotEmpty, 'sessionId must not be empty');
    _require(peerMmId.startsWith('mm:'), 'peerMmId must start with mm:');
    _require(suiteId.isNotEmpty, 'suiteId must not be empty');
  }

  final String sessionId;
  final String peerMmId;
  final String suiteId;
}

final class EncryptedApplicationEnvelope {
  EncryptedApplicationEnvelope({
    required this.formatVersion,
    required this.suiteId,
    required this.logicalMessageId,
    required this.senderMmId,
    required this.recipientMmId,
    required this.sessionId,
    required this.ciphertextBase64,
  }) {
    _require(formatVersion > 0, 'formatVersion must be positive');
    _require(suiteId.isNotEmpty, 'suiteId must not be empty');
    _require(logicalMessageId.isNotEmpty, 'logicalMessageId must not be empty');
    _require(senderMmId.startsWith('mm:'), 'senderMmId must start with mm:');
    _require(recipientMmId.startsWith('mm:'), 'recipientMmId must start with mm:');
    _require(sessionId.isNotEmpty, 'sessionId must not be empty');
    _require(ciphertextBase64.isNotEmpty, 'ciphertextBase64 must not be empty');
  }

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'suiteId': suiteId,
    'logicalMessageId': logicalMessageId,
    'senderMmId': senderMmId,
    'recipientMmId': recipientMmId,
    'sessionId': sessionId,
    'ciphertextBase64': ciphertextBase64,
  };

  String encode() => jsonEncode(toJson());

  factory EncryptedApplicationEnvelope.fromJson(Map<String, dynamic> json) =>
      EncryptedApplicationEnvelope(
        formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
        suiteId: json['suiteId'] as String? ?? '',
        logicalMessageId: json['logicalMessageId'] as String? ?? '',
        senderMmId: json['senderMmId'] as String? ?? '',
        recipientMmId: json['recipientMmId'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        ciphertextBase64: json['ciphertextBase64'] as String? ?? '',
      );

  factory EncryptedApplicationEnvelope.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('M07_ENVELOPE_INVALID');
    }
    return EncryptedApplicationEnvelope.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  final int formatVersion;
  final String suiteId;
  final String logicalMessageId;
  final String senderMmId;
  final String recipientMmId;
  final String sessionId;
  final String ciphertextBase64;
}

final class DirectPlaintext {
  DirectPlaintext({
    required this.logicalMessageId,
    required this.senderMmId,
    required this.recipientMmId,
    required this.conversationKey,
    required this.messageClass,
    required this.payloadUtf8,
  }) {
    _require(logicalMessageId.isNotEmpty, 'logicalMessageId must not be empty');
    _require(senderMmId.startsWith('mm:'), 'senderMmId must start with mm:');
    _require(recipientMmId.startsWith('mm:'), 'recipientMmId must start with mm:');
    _require(conversationKey.isNotEmpty, 'conversationKey must not be empty');
    _require(messageClass.isNotEmpty, 'messageClass must not be empty');
  }

  final String logicalMessageId;
  final String senderMmId;
  final String recipientMmId;
  final String conversationKey;
  final String messageClass;
  final String payloadUtf8;
}

sealed class DirectDecryptResult {
  const DirectDecryptResult();
}

final class DirectDecryptSuccess extends DirectDecryptResult {
  const DirectDecryptSuccess(this.plaintext);
  final DirectPlaintext plaintext;
}

final class DirectDecryptRejected extends DirectDecryptResult {
  const DirectDecryptRejected(this.reason);
  final String reason;
}

final class AttachmentManifest {
  AttachmentManifest({
    required this.transferId,
    required this.logicalMessageId,
    required this.sizeBytes,
    required this.contentHash,
    required this.mediaType,
  }) {
    _require(transferId.isNotEmpty, 'transferId must not be empty');
    _require(logicalMessageId.isNotEmpty, 'logicalMessageId must not be empty');
    _require(sizeBytes >= 0, 'sizeBytes must not be negative');
    _require(contentHash.isNotEmpty, 'contentHash must not be empty');
    _require(mediaType.isNotEmpty, 'mediaType must not be empty');
  }

  final String transferId;
  final String logicalMessageId;
  final int sizeBytes;
  final String contentHash;
  final String mediaType;
}

final class AttachmentCryptoRef {
  AttachmentCryptoRef({
    required this.transferId,
    required this.keyHandle,
    required this.encryptedManifestBase64,
  }) {
    _require(transferId.isNotEmpty, 'transferId must not be empty');
    _require(keyHandle.isNotEmpty, 'keyHandle must not be empty');
    _require(
      encryptedManifestBase64.isNotEmpty,
      'encryptedManifestBase64 must not be empty',
    );
  }

  final String transferId;
  final String keyHandle;
  final String encryptedManifestBase64;
}

final class PairwiseRelayBinding {
  PairwiseRelayBinding({
    required this.bindingId,
    required this.localContactMmId,
    required this.relayId,
    required this.inboundHandle,
    required this.credentialRef,
    this.expiresAtEpochMs,
  }) {
    _require(bindingId.isNotEmpty, 'bindingId must not be empty');
    _require(
      localContactMmId.startsWith('mm:'),
      'localContactMmId must start with mm:',
    );
    _require(relayId.isNotEmpty, 'relayId must not be empty');
    _require(inboundHandle.isNotEmpty, 'inboundHandle must not be empty');
    _require(credentialRef.isNotEmpty, 'credentialRef must not be empty');
  }

  final String bindingId;
  final String localContactMmId;
  final String relayId;
  final String inboundHandle;
  final String credentialRef;
  final int? expiresAtEpochMs;
}

final class TransportPrivacyEnvelope {
  TransportPrivacyEnvelope({
    required this.attemptId,
    required this.opaqueRoutingHandle,
    required this.wrappedPayloadBase64,
    this.paddingClass,
  }) {
    _require(attemptId.isNotEmpty, 'attemptId must not be empty');
    _require(
      opaqueRoutingHandle.isNotEmpty,
      'opaqueRoutingHandle must not be empty',
    );
    _require(
      wrappedPayloadBase64.isNotEmpty,
      'wrappedPayloadBase64 must not be empty',
    );
  }

  final String attemptId;
  final String opaqueRoutingHandle;
  final String wrappedPayloadBase64;
  final String? paddingClass;
}

/// M07 security boundary shared conceptually with the Kotlin implementation.
///
/// Concrete cryptography must come from a maintained, reviewed provider.
/// UI, M02, M05, M12 and transport adapters must not implement their own
/// Signal/PQXDH/ratchet logic.
abstract interface class M07CryptoProvider {
  IdentityPublicMaterial localIdentity();

  M07SuiteProfile get suiteProfile;

  /// Returns the current signed asynchronous-session bootstrap bundle.
  Future<PortablePreKeyBundle> localPreKeyBundle();

  /// Imports provider-verified peer bootstrap material.
  ///
  /// Implementations MUST authenticate the signed prekey against the peer
  /// identity, enforce expiry/epoch rollback rules and fail closed on
  /// forbidden suite downgrade.
  Future<void> importPeerPreKeyBundle(PortablePreKeyBundle bundle);

  bool verifyIdentityBinding(IdentityPublicMaterial identity);

  Future<SecureSessionRef> ensureDirectSession(
    IdentityPublicMaterial peer,
  );

  /// Advances the secure session exactly once for one logical message/recipient.
  ///
  /// All transport retries/racing must reuse the returned immutable envelope.
  Future<EncryptedApplicationEnvelope> encryptDirect(
    DirectPlaintext plaintext,
  );

  Future<DirectDecryptResult> decryptDirect(
    EncryptedApplicationEnvelope envelope,
  );

  /// Creates an attachment secret inside the provider.
  ///
  /// M05 only receives an opaque local key handle and encrypted manifest.
  Future<AttachmentCryptoRef> createAttachmentCrypto(
    SecureSessionRef session,
    AttachmentManifest manifest,
  );

  Future<Uint8List> encryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List plaintext,
  );

  Future<Uint8List> decryptAttachmentChunk(
    AttachmentCryptoRef attachment,
    int chunkIndex,
    Uint8List ciphertext,
  );
}
