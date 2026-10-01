import 'dart:async';
import 'dart:convert';

import 'app_storage.dart';
import 'delivery.dart';
import 'm07_security.dart';
import 'models.dart';

final class MeshMessengerCore {
  MeshMessengerCore({
    required this.ownMmId,
    required AppStorage storage,
    required List<MessageTransport> transports,
    M07CryptoProvider? cryptoProvider,
    this.requirePrivateE2ee = false,
    DateTime Function()? now,
  }) : _storage = storage,
       _cryptoProvider = cryptoProvider,
       _now = now ?? (() => DateTime.now().toUtc()),
       delivery = DeliveryManager(
         storage: storage,
         transports: transports,
         now: now,
       );

  final String ownMmId;
  final AppStorage _storage;
  final M07CryptoProvider? _cryptoProvider;
  final bool requirePrivateE2ee;
  final DateTime Function() _now;
  final DeliveryManager delivery;
  int _secureIdCounter = 0;

  Stream<DeliveryEnvelope> get deliveryChanges => delivery.changes;
  List<DeliveryEnvelope> get pending => delivery.pending;

  Future<void> restore() async {
    await delivery.restore();
    await _recoverAtomicCryptoCommits();
  }

  Future<List<Contact>> contacts() => _storage.loadContacts();
  Future<void> saveContact(Contact contact) => _storage.saveContact(contact);
  Future<List<GroupDefinition>> groups() => _storage.loadGroups();
  Future<void> saveGroup(GroupDefinition group) => _storage.saveGroup(group);
  Future<List<GroupReceiptRecord>> groupReceipts() =>
      _storage.loadGroupReceipts();
  Future<List<ConversationMessage>> messagesFor(String peerMmId) =>
      _storage.loadMessages(peerMmId: peerMmId);

  Future<List<ConversationMessage>> messagesForConversation(
    ConversationRef conversation,
  ) => _storage.loadMessages(conversationKey: conversation.key);
  Future<List<ConversationMessage>> allMessages() => _storage.loadMessages();
  DeliveryEnvelope? deliveryById(String id) => delivery.byId(id);
  Future<void> maintenance() => delivery.maintenance();

  Future<DeliveryEnvelope> sendText({
    required String peerMmId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('text must not be empty');
    final messageId = _newLogicalMessageId('m');
    final provider = _cryptoProvider;
    final DeliveryEnvelope result;
    M07AtomicCryptoProvider? atomicProviderToAck;
    String? atomicCommitIdToAck;
    if (provider == null) {
      if (requirePrivateE2ee) throw StateError('M07_PRIVATE_E2EE_REQUIRED');
      result = await delivery.enqueue(
        recipientMmId: peerMmId,
        messageClass: 'text',
        payload: clean,
        messageId: messageId,
      );
    } else {
      final atomic = provider is M07AtomicCryptoProvider ? provider : null;
      if (atomic == null) {
        final encrypted = await _encryptPrivate(
          recipientMmId: peerMmId,
          logicalMessageId: messageId,
          conversationKey: m07DirectSecurityContext(ownMmId, peerMmId),
          messageClass: 'text',
          payloadUtf8: clean,
        );
        result = await delivery.enqueue(
          recipientMmId: peerMmId,
          messageClass: m07DirectEnvelopeClass,
          payload: encrypted.encode(),
          messageId: messageId,
        );
      } else {
        final commit = await _encryptPrivateAtomic(
          provider: atomic,
          recipientMmId: peerMmId,
          logicalMessageId: messageId,
          conversationKey: m07DirectSecurityContext(ownMmId, peerMmId),
          messageClass: 'text',
          payloadUtf8: clean,
          recoveryContext: <String, Object?>{
            'kind': 'direct_text_out',
            'messageId': messageId,
            'peerMmId': peerMmId,
            'text': clean,
            'createdAt': _now().toIso8601String(),
          },
        );
        result = await delivery.enqueue(
          recipientMmId: peerMmId,
          messageClass: m07DirectEnvelopeClass,
          payload: commit.envelope.encode(),
          messageId: messageId,
        );
        atomicProviderToAck = atomic;
        atomicCommitIdToAck = commit.commitId;
      }
    }
    await _storage.appendMessageUnique(
      ConversationMessage(
        messageId: result.messageId,
        peerMmId: peerMmId,
        text: clean,
        outgoing: true,
        createdAt: _now(),
        conversationKey: ConversationRef.direct(peerMmId).key,
        senderMmId: ownMmId,
      ),
    );
    if (atomicProviderToAck != null && atomicCommitIdToAck != null) {
      await atomicProviderToAck.markOutboundCommitPersisted(
        atomicCommitIdToAck,
      );
    }
    return result;
  }

  Future<DeliveryEnvelope> sendChannelText({
    required String channelId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('text must not be empty');
    final target = channelTargetKey(channelId);
    final result = await delivery.enqueue(
      recipientMmId: target,
      messageClass: 'text',
      payload: clean,
    );
    await _storage.appendMessageUnique(
      ConversationMessage(
        messageId: result.messageId,
        peerMmId: target,
        text: clean,
        outgoing: true,
        createdAt: _now(),
        conversationKey: ConversationRef.channel(channelId).key,
        senderMmId: ownMmId,
      ),
    );
    return result;
  }

  Future<GroupDefinition> createGroup({
    required String displayName,
    required Iterable<String> memberMmIds,
  }) async {
    final cleanName = displayName.trim();
    if (cleanName.isEmpty) throw ArgumentError('group name must not be empty');
    final now = _now();
    final members = <String>{ownMmId, ...memberMmIds.map((e) => e.trim())}
      ..removeWhere((e) => e.isEmpty);
    if (members.length < 2) {
      throw ArgumentError('group requires at least one remote member');
    }
    final group = GroupDefinition(
      groupId: 'g-${now.microsecondsSinceEpoch}',
      displayName: cleanName,
      creatorMmId: ownMmId,
      memberMmIds: members.toList(growable: false)..sort(),
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveGroup(group);
    return group;
  }

  Future<bool> upsertGroupDescriptor({
    required GroupDefinition descriptor,
    required String fromMmId,
  }) async {
    if (descriptor.groupId.trim().isEmpty ||
        descriptor.displayName.trim().isEmpty ||
        descriptor.creatorMmId != fromMmId ||
        !descriptor.contains(ownMmId) ||
        !descriptor.contains(fromMmId)) {
      return false;
    }
    final knownCreator = (await contacts()).any((c) => c.mmId == fromMmId);
    if (!knownCreator) return false;
    final existing = (await groups())
        .where((g) => g.groupId == descriptor.groupId)
        .firstOrNull;
    if (existing != null) {
      if (existing.creatorMmId != descriptor.creatorMmId ||
          descriptor.revision <= existing.revision) {
        return false;
      }
    }
    await _storage.saveGroup(descriptor);
    return true;
  }

  Future<List<DeliveryEnvelope>> sendGroupText({
    required String groupId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('text must not be empty');
    final group = (await groups())
        .where((g) => g.groupId == groupId)
        .firstOrNull;
    if (group == null) throw StateError('GROUP_NOT_FOUND');
    if (!group.contains(ownMmId)) throw StateError('GROUP_NOT_MEMBER');
    final now = _now();
    final messageId = _newLogicalMessageId('gm');
    final provider = _cryptoProvider;
    if (provider == null && requirePrivateE2ee) {
      throw StateError('M07_PRIVATE_E2EE_REQUIRED');
    }
    final legs = <DeliveryEnvelope>[];
    for (final member in group.memberMmIds) {
      if (member == ownMmId) continue;
      final legId = '$messageId@$member';
      final String messageClass;
      final String payload;
      if (provider == null) {
        messageClass = 'text';
        payload = clean;
      } else {
        final encrypted = await _encryptPrivate(
          recipientMmId: member,
          logicalMessageId: messageId,
          conversationKey: ConversationRef.group(groupId).key,
          messageClass: 'text',
          payloadUtf8: clean,
        );
        messageClass = m07DirectEnvelopeClass;
        payload = encrypted.encode();
      }
      legs.add(
        await delivery.enqueue(
          recipientMmId: groupTargetKey(groupId, member),
          messageClass: messageClass,
          payload: payload,
          messageId: messageId,
          deliveryId: legId,
          groupRevision: group.revision,
        ),
      );
    }
    await _storage.appendMessageUnique(
      ConversationMessage(
        messageId: messageId,
        peerMmId: 'group:$groupId',
        text: clean,
        outgoing: true,
        createdAt: now,
        conversationKey: ConversationRef.group(groupId).key,
        senderMmId: ownMmId,
      ),
    );
    return legs;
  }

  Future<bool> receiveGroupText({
    required String messageId,
    required String fromMmId,
    required String groupId,
    required int membershipRevision,
    required String text,
  }) {
    if (requirePrivateE2ee) {
      throw StateError('M07_PLAINTEXT_INGRESS_REJECTED');
    }
    return _storeReceivedGroupText(
      messageId: messageId,
      fromMmId: fromMmId,
      groupId: groupId,
      membershipRevision: membershipRevision,
      text: text,
    );
  }

  Future<bool> _storeReceivedGroupText({
    required String messageId,
    required String fromMmId,
    required String groupId,
    required int membershipRevision,
    required String text,
  }) async {
    final group = (await groups())
        .where((g) => g.groupId == groupId)
        .firstOrNull;
    if (group == null ||
        !group.contains(ownMmId) ||
        !group.contains(fromMmId)) {
      return false;
    }
    if (membershipRevision > group.revision) return false;
    return _storage.appendMessageUnique(
      ConversationMessage(
        messageId: messageId,
        peerMmId: 'group:$groupId',
        text: text,
        outgoing: false,
        createdAt: _now(),
        conversationKey: ConversationRef.group(groupId).key,
        senderMmId: fromMmId,
      ),
    );
  }

  Future<DeliveryEnvelope?> receiveGroupReceipt({
    required String messageId,
    required String fromMmId,
    required String groupId,
  }) async {
    final group = (await groups())
        .where((g) => g.groupId == groupId)
        .firstOrNull;
    if (group == null || !group.contains(fromMmId)) return null;
    await _storage.saveGroupReceipt(
      GroupReceiptRecord(
        messageId: messageId,
        groupId: groupId,
        memberMmId: fromMmId,
        receivedAt: _now(),
      ),
    );
    return delivery.recipientResult(
      messageId: messageId,
      fromMmId: fromMmId,
      ok: true,
    );
  }

  Future<bool> receiveText({
    required String messageId,
    required String fromMmId,
    required String text,
  }) {
    if (requirePrivateE2ee) {
      throw StateError('M07_PLAINTEXT_INGRESS_REJECTED');
    }
    return _storeReceivedText(
      messageId: messageId,
      fromMmId: fromMmId,
      text: text,
    );
  }

  Future<bool> _storeReceivedText({
    required String messageId,
    required String fromMmId,
    required String text,
  }) => _storage.appendMessageUnique(
    ConversationMessage(
      messageId: messageId,
      peerMmId: fromMmId,
      text: text,
      outgoing: false,
      createdAt: _now(),
      conversationKey: ConversationRef.direct(fromMmId).key,
      senderMmId: fromMmId,
    ),
  );

  Future<bool> receiveChannelText({
    required String messageId,
    required String fromMmId,
    required String channelId,
    required String text,
  }) => _storage.appendMessageUnique(
    ConversationMessage(
      messageId: messageId,
      peerMmId: channelTargetKey(channelId),
      text: text,
      outgoing: false,
      createdAt: _now(),
      conversationKey: ConversationRef.channel(channelId).key,
      senderMmId: fromMmId,
    ),
  );

  Future<DeliveryEnvelope> sendChannelMapPoint({
    required String channelId,
    required MapPoint point,
  }) async {
    final target = channelTargetKey(channelId);
    final result = await delivery.enqueue(
      recipientMmId: target,
      messageClass: 'map_point',
      payload: jsonEncode(point.toJson()),
    );
    await _storage.appendMessageUnique(
      ConversationMessage(
        messageId: result.messageId,
        peerMmId: target,
        text: point.label.isEmpty ? 'Точка на карте' : point.label,
        outgoing: true,
        createdAt: _now(),
        messageClass: 'map_point',
        mapPoint: point,
        conversationKey: ConversationRef.channel(channelId).key,
        senderMmId: ownMmId,
      ),
    );
    return result;
  }

  Future<bool> receiveChannelMapPoint({
    required String messageId,
    required String fromMmId,
    required String channelId,
    required String payload,
  }) async {
    final raw = jsonDecode(payload);
    if (raw is! Map) throw const FormatException('MAP_POINT_INVALID');
    final point = MapPoint.fromJson(raw.cast<String, dynamic>());
    if (point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      throw const FormatException('MAP_POINT_COORDINATES_INVALID');
    }
    return _storage.appendMessageUnique(
      ConversationMessage(
        messageId: messageId,
        peerMmId: channelTargetKey(channelId),
        text: point.label.isEmpty ? 'Точка на карте' : point.label,
        outgoing: false,
        createdAt: _now(),
        messageClass: 'map_point',
        mapPoint: point,
        conversationKey: ConversationRef.channel(channelId).key,
        senderMmId: fromMmId,
      ),
    );
  }

  Future<DeliveryEnvelope> sendMapPoint({
    required String peerMmId,
    required MapPoint point,
  }) async {
    final messageId = _newLogicalMessageId('m');
    final clearPayload = jsonEncode(point.toJson());
    final provider = _cryptoProvider;
    final DeliveryEnvelope result;
    M07AtomicCryptoProvider? atomicProviderToAck;
    String? atomicCommitIdToAck;
    if (provider == null) {
      if (requirePrivateE2ee) throw StateError('M07_PRIVATE_E2EE_REQUIRED');
      result = await delivery.enqueue(
        recipientMmId: peerMmId,
        messageClass: 'map_point',
        payload: clearPayload,
        messageId: messageId,
      );
    } else {
      final atomic = provider is M07AtomicCryptoProvider ? provider : null;
      if (atomic == null) {
        final encrypted = await _encryptPrivate(
          recipientMmId: peerMmId,
          logicalMessageId: messageId,
          conversationKey: m07DirectSecurityContext(ownMmId, peerMmId),
          messageClass: 'map_point',
          payloadUtf8: clearPayload,
        );
        result = await delivery.enqueue(
          recipientMmId: peerMmId,
          messageClass: m07DirectEnvelopeClass,
          payload: encrypted.encode(),
          messageId: messageId,
        );
      } else {
        final commit = await _encryptPrivateAtomic(
          provider: atomic,
          recipientMmId: peerMmId,
          logicalMessageId: messageId,
          conversationKey: m07DirectSecurityContext(ownMmId, peerMmId),
          messageClass: 'map_point',
          payloadUtf8: clearPayload,
          recoveryContext: <String, Object?>{
            'kind': 'direct_map_out',
            'messageId': messageId,
            'peerMmId': peerMmId,
            'point': point.toJson(),
            'createdAt': _now().toIso8601String(),
          },
        );
        result = await delivery.enqueue(
          recipientMmId: peerMmId,
          messageClass: m07DirectEnvelopeClass,
          payload: commit.envelope.encode(),
          messageId: messageId,
        );
        atomicProviderToAck = atomic;
        atomicCommitIdToAck = commit.commitId;
      }
    }
    await _storage.appendMessageUnique(
      ConversationMessage(
        messageId: result.messageId,
        peerMmId: peerMmId,
        text: point.label.isEmpty ? 'Точка на карте' : point.label,
        outgoing: true,
        createdAt: _now(),
        messageClass: 'map_point',
        mapPoint: point,
        conversationKey: ConversationRef.direct(peerMmId).key,
        senderMmId: ownMmId,
      ),
    );
    if (atomicProviderToAck != null && atomicCommitIdToAck != null) {
      await atomicProviderToAck.markOutboundCommitPersisted(
        atomicCommitIdToAck,
      );
    }
    return result;
  }

  Future<bool> receiveMapPoint({
    required String messageId,
    required String fromMmId,
    required String payload,
  }) {
    if (requirePrivateE2ee) {
      throw StateError('M07_PLAINTEXT_INGRESS_REJECTED');
    }
    return _storeReceivedMapPoint(
      messageId: messageId,
      fromMmId: fromMmId,
      payload: payload,
    );
  }

  Future<bool> _storeReceivedMapPoint({
    required String messageId,
    required String fromMmId,
    required String payload,
  }) async {
    final raw = jsonDecode(payload);
    if (raw is! Map) throw const FormatException('MAP_POINT_INVALID');
    final point = MapPoint.fromJson(raw.cast<String, dynamic>());
    if (point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      throw const FormatException('MAP_POINT_COORDINATES_INVALID');
    }
    return _storage.appendMessageUnique(
      ConversationMessage(
        messageId: messageId,
        peerMmId: fromMmId,
        text: point.label.isEmpty ? 'Точка на карте' : point.label,
        outgoing: false,
        createdAt: _now(),
        messageClass: 'map_point',
        mapPoint: point,
        conversationKey: ConversationRef.direct(fromMmId).key,
        senderMmId: fromMmId,
      ),
    );
  }

  Future<DeliveryEnvelope?> acknowledge(String messageId, String fromMmId) =>
      delivery.acknowledge(messageId: messageId, fromMmId: fromMmId);

  Future<DeliveryEnvelope?> recipientDeliveryResult({
    required String messageId,
    required String fromMmId,
    required bool ok,
    String? detail,
    bool hardFailure = false,
  }) => delivery.recipientResult(
    messageId: messageId,
    fromMmId: fromMmId,
    ok: ok,
    detail: detail,
    hardFailure: hardFailure,
  );

  String _newLogicalMessageId(String prefix) {
    final now = _now();
    return '$prefix-${now.microsecondsSinceEpoch}-${++_secureIdCounter}';
  }

  Future<Contact> _peerContact(String peerMmId) async {
    final contact = (await contacts())
        .where((c) => c.mmId == peerMmId)
        .firstOrNull;
    if (contact == null) throw StateError('M07_CONTACT_REQUIRED');
    return contact;
  }

  IdentityPublicMaterial _peerIdentity(Contact contact) {
    final identityKey = contact.identityPublicKey?.trim() ?? '';
    final fingerprint = contact.fingerprint?.trim() ?? '';
    if (identityKey.isEmpty || fingerprint.isEmpty) {
      throw StateError('M07_PEER_IDENTITY_REQUIRED');
    }
    return IdentityPublicMaterial(
      formatVersion: 1,
      mmId: contact.mmId,
      fingerprint: fingerprint,
      identityPublicKey: identityKey,
      devicePublicKey: contact.agreementPublicKey?.trim().isNotEmpty == true
          ? contact.agreementPublicKey!.trim()
          : null,
    );
  }

  Future<EncryptedApplicationEnvelope> _encryptPrivate({
    required String recipientMmId,
    required String logicalMessageId,
    required String conversationKey,
    required String messageClass,
    required String payloadUtf8,
  }) async {
    final provider = _cryptoProvider;
    if (provider == null) throw StateError('M07_PRIVATE_E2EE_REQUIRED');
    final contact = await _peerContact(recipientMmId);
    final peer = _peerIdentity(contact);
    if (!provider.verifyIdentityBinding(peer)) {
      throw StateError('M07_IDENTITY_BINDING_REJECTED');
    }
    PortablePreKeyBundle? preKeyBundle;
    final rawBundle = contact.preKeyBundle?.trim() ?? '';
    if (rawBundle.isNotEmpty) {
      preKeyBundle = PortablePreKeyBundle.decode(rawBundle);
      if (preKeyBundle.mmId != recipientMmId ||
          preKeyBundle.identityPublicKey != peer.identityPublicKey) {
        throw StateError('M07_PREKEY_BINDING_REJECTED');
      }
    }
    await provider.ensureDirectSession(peer, preKeyBundle: preKeyBundle);
    final encrypted = await provider.encryptDirect(
      DirectPlaintext(
        logicalMessageId: logicalMessageId,
        senderMmId: ownMmId,
        recipientMmId: recipientMmId,
        conversationKey: conversationKey,
        messageClass: messageClass,
        payloadUtf8: payloadUtf8,
      ),
    );
    return encrypted;
  }

  Future<DirectPlaintext> _decryptPrivate({
    required String expectedMessageId,
    required String expectedFromMmId,
    required String encodedEnvelope,
  }) async {
    final provider = _cryptoProvider;
    if (provider == null) throw StateError('M07_PRIVATE_E2EE_REQUIRED');
    final envelope = EncryptedApplicationEnvelope.decode(encodedEnvelope);
    final result = await provider.decryptDirect(
      envelope,
      expectedLogicalMessageId: expectedMessageId,
      expectedSenderMmId: expectedFromMmId,
      expectedRecipientMmId: ownMmId,
    );
    if (result is! DirectDecryptSuccess) {
      throw const FormatException('M07_DECRYPT_REJECTED');
    }
    final plaintext = result.plaintext;
    if (plaintext.logicalMessageId != expectedMessageId ||
        plaintext.senderMmId != expectedFromMmId ||
        plaintext.recipientMmId != ownMmId) {
      throw const FormatException('M07_PLAINTEXT_BINDING_MISMATCH');
    }
    return plaintext;
  }

  Future<bool> receiveEncryptedDirect({
    required String messageId,
    required String fromMmId,
    required String encodedEnvelope,
  }) async {
    final provider = _cryptoProvider;
    final atomic = provider is M07AtomicCryptoProvider ? provider : null;
    if (atomic == null) {
      final plaintext = await _decryptPrivate(
        expectedMessageId: messageId,
        expectedFromMmId: fromMmId,
        encodedEnvelope: encodedEnvelope,
      );
      return _storeValidatedDirectPlaintext(
        messageId: messageId,
        fromMmId: fromMmId,
        plaintext: plaintext,
      );
    }

    final contact = await _peerContact(fromMmId);
    final peer = _peerIdentity(contact);
    if (!atomic.verifyIdentityBinding(peer)) {
      throw StateError('M07_IDENTITY_BINDING_REJECTED');
    }
    final outcome = await atomic.decryptDirectAtomic(
      peer: peer,
      envelope: EncryptedApplicationEnvelope.decode(encodedEnvelope),
      expectedLogicalMessageId: messageId,
      expectedSenderMmId: fromMmId,
      expectedRecipientMmId: ownMmId,
      recoveryContextJson: jsonEncode(<String, Object?>{
        'kind': 'direct_in',
        'messageId': messageId,
        'fromMmId': fromMmId,
      }),
    );
    if (outcome is M07AtomicDecryptRejected) {
      throw FormatException('M07_DECRYPT_REJECTED:${outcome.rejection.reason}');
    }
    final commit = outcome as M07AtomicInboundCommit;
    final stored = await _storeValidatedDirectPlaintext(
      messageId: messageId,
      fromMmId: fromMmId,
      plaintext: commit.plaintext,
    );
    await atomic.markInboundCommitPersisted(commit.commitId);
    return stored;
  }

  Future<M07AtomicOutboundCommit> _encryptPrivateAtomic({
    required M07AtomicCryptoProvider provider,
    required String recipientMmId,
    required String logicalMessageId,
    required String conversationKey,
    required String messageClass,
    required String payloadUtf8,
    required Map<String, Object?> recoveryContext,
  }) async {
    final contact = await _peerContact(recipientMmId);
    final peer = _peerIdentity(contact);
    if (!provider.verifyIdentityBinding(peer)) {
      throw StateError('M07_IDENTITY_BINDING_REJECTED');
    }
    PortablePreKeyBundle? preKeyBundle;
    final rawBundle = contact.preKeyBundle?.trim() ?? '';
    if (rawBundle.isNotEmpty) {
      preKeyBundle = PortablePreKeyBundle.decode(rawBundle);
      if (preKeyBundle.mmId != recipientMmId ||
          preKeyBundle.identityPublicKey != peer.identityPublicKey) {
        throw StateError('M07_PREKEY_BINDING_REJECTED');
      }
    }
    return provider.encryptDirectAtomic(
      peer: peer,
      preKeyBundle: preKeyBundle,
      plaintext: DirectPlaintext(
        logicalMessageId: logicalMessageId,
        senderMmId: ownMmId,
        recipientMmId: recipientMmId,
        conversationKey: conversationKey,
        messageClass: messageClass,
        payloadUtf8: payloadUtf8,
      ),
      recoveryContextJson: jsonEncode(recoveryContext),
    );
  }

  Future<bool> _storeValidatedDirectPlaintext({
    required String messageId,
    required String fromMmId,
    required DirectPlaintext plaintext,
  }) {
    if (plaintext.logicalMessageId != messageId ||
        plaintext.senderMmId != fromMmId ||
        plaintext.recipientMmId != ownMmId) {
      throw const FormatException('M07_PLAINTEXT_BINDING_MISMATCH');
    }
    if (plaintext.conversationKey !=
        m07DirectSecurityContext(ownMmId, fromMmId)) {
      throw const FormatException('M07_DIRECT_CONVERSATION_MISMATCH');
    }
    switch (plaintext.messageClass) {
      case 'text':
        return _storeReceivedText(
          messageId: messageId,
          fromMmId: fromMmId,
          text: plaintext.payloadUtf8,
        );
      case 'map_point':
        return _storeReceivedMapPoint(
          messageId: messageId,
          fromMmId: fromMmId,
          payload: plaintext.payloadUtf8,
        );
      default:
        throw const FormatException('M07_MESSAGE_CLASS_UNSUPPORTED');
    }
  }

  Future<void> _recoverAtomicCryptoCommits() async {
    final provider = _cryptoProvider;
    if (provider is! M07AtomicCryptoProvider) return;

    for (final commit in await provider.pendingOutboundCommits()) {
      final raw = jsonDecode(commit.recoveryContextJson);
      if (raw is! Map) {
        throw const FormatException('M07_RECOVERY_CONTEXT_INVALID');
      }
      final context = Map<String, dynamic>.from(raw);
      final kind = context['kind'];
      final messageId = context['messageId'] as String? ?? '';
      final peerMmId = context['peerMmId'] as String? ?? '';
      if (messageId.isEmpty || peerMmId.isEmpty) {
        throw const FormatException('M07_RECOVERY_CONTEXT_INVALID');
      }
      if (delivery.byId(messageId) == null) {
        await delivery.enqueue(
          recipientMmId: peerMmId,
          messageClass: m07DirectEnvelopeClass,
          payload: commit.envelope.encode(),
          messageId: messageId,
        );
      }
      if (kind == 'direct_text_out') {
        await _storage.appendMessageUnique(
          ConversationMessage(
            messageId: messageId,
            peerMmId: peerMmId,
            text: context['text'] as String? ?? '',
            outgoing: true,
            createdAt:
                DateTime.tryParse(context['createdAt'] as String? ?? '') ??
                _now(),
            conversationKey: ConversationRef.direct(peerMmId).key,
            senderMmId: ownMmId,
          ),
        );
      } else if (kind == 'direct_map_out') {
        final pointRaw = context['point'];
        if (pointRaw is! Map) {
          throw const FormatException('M07_RECOVERY_MAP_INVALID');
        }
        final point = MapPoint.fromJson(Map<String, dynamic>.from(pointRaw));
        await _storage.appendMessageUnique(
          ConversationMessage(
            messageId: messageId,
            peerMmId: peerMmId,
            text: point.label.isEmpty ? 'Точка на карте' : point.label,
            outgoing: true,
            createdAt:
                DateTime.tryParse(context['createdAt'] as String? ?? '') ??
                _now(),
            messageClass: 'map_point',
            mapPoint: point,
            conversationKey: ConversationRef.direct(peerMmId).key,
            senderMmId: ownMmId,
          ),
        );
      } else {
        throw const FormatException('M07_RECOVERY_KIND_UNSUPPORTED');
      }
      await provider.markOutboundCommitPersisted(commit.commitId);
    }

    for (final commit in await provider.pendingInboundCommits()) {
      final raw = jsonDecode(commit.recoveryContextJson);
      if (raw is! Map) {
        throw const FormatException('M07_RECOVERY_CONTEXT_INVALID');
      }
      final context = Map<String, dynamic>.from(raw);
      if (context['kind'] != 'direct_in') {
        throw const FormatException('M07_RECOVERY_KIND_UNSUPPORTED');
      }
      final messageId = context['messageId'] as String? ?? '';
      final fromMmId = context['fromMmId'] as String? ?? '';
      if (messageId.isEmpty || fromMmId.isEmpty) {
        throw const FormatException('M07_RECOVERY_CONTEXT_INVALID');
      }
      await _storeValidatedDirectPlaintext(
        messageId: messageId,
        fromMmId: fromMmId,
        plaintext: commit.plaintext,
      );
      await provider.markInboundCommitPersisted(commit.commitId);
    }
  }

  Future<bool> receiveEncryptedGroup({
    required String messageId,
    required String fromMmId,
    required String groupId,
    required int membershipRevision,
    required String encodedEnvelope,
  }) async {
    final plaintext = await _decryptPrivate(
      expectedMessageId: messageId,
      expectedFromMmId: fromMmId,
      encodedEnvelope: encodedEnvelope,
    );
    if (plaintext.conversationKey != ConversationRef.group(groupId).key) {
      throw const FormatException('M07_GROUP_CONVERSATION_MISMATCH');
    }
    if (plaintext.messageClass != 'text') {
      throw const FormatException('M07_GROUP_CLASS_UNSUPPORTED');
    }
    return _storeReceivedGroupText(
      messageId: messageId,
      fromMmId: fromMmId,
      groupId: groupId,
      membershipRevision: membershipRevision,
      text: plaintext.payloadUtf8,
    );
  }

  Future<void> close() => delivery.close();
}
