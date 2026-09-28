import 'dart:typed_data';

void _require(bool condition, String message) {
  if (!condition) throw ArgumentError(message);
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
