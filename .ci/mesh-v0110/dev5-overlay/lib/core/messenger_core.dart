import 'dart:async';
import 'dart:convert';

import 'app_storage.dart';
import 'delivery.dart';
import 'models.dart';

final class MeshMessengerCore {
  MeshMessengerCore({
    required this.ownMmId,
    required AppStorage storage,
    required List<MessageTransport> transports,
    DateTime Function()? now,
  }) : _storage = storage,
       _now = now ?? (() => DateTime.now().toUtc()),
       delivery = DeliveryManager(
         storage: storage,
         transports: transports,
         now: now,
       );

  final String ownMmId;
  final AppStorage _storage;
  final DateTime Function() _now;
  final DeliveryManager delivery;

  Stream<DeliveryEnvelope> get deliveryChanges => delivery.changes;
  List<DeliveryEnvelope> get pending => delivery.pending;

  Future<void> restore() => delivery.restore();
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
  DeliveryEnvelope? deliveryById(String id) => delivery.byId(id);
  Future<void> maintenance() => delivery.maintenance();

  Future<DeliveryEnvelope> sendText({
    required String peerMmId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('text must not be empty');
    final result = await delivery.sendText(
      recipientMmId: peerMmId,
      text: clean,
    );
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
    final existing =
        (await groups()).where((g) => g.groupId == descriptor.groupId).firstOrNull;
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
    final group = (await groups()).where((g) => g.groupId == groupId).firstOrNull;
    if (group == null) throw StateError('GROUP_NOT_FOUND');
    if (!group.contains(ownMmId)) throw StateError('GROUP_NOT_MEMBER');
    final now = _now();
    final messageId = 'gm-${now.microsecondsSinceEpoch}';
    final legs = <DeliveryEnvelope>[];
    for (final member in group.memberMmIds) {
      if (member == ownMmId) continue;
      final legId = '$messageId@$member';
      legs.add(
        await delivery.enqueue(
          recipientMmId: groupTargetKey(groupId, member),
          messageClass: 'text',
          payload: clean,
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
  }) async {
    final group = (await groups()).where((g) => g.groupId == groupId).firstOrNull;
    if (group == null || !group.contains(ownMmId) || !group.contains(fromMmId)) {
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
    final group = (await groups()).where((g) => g.groupId == groupId).firstOrNull;
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
    final result = await delivery.enqueue(
      recipientMmId: peerMmId,
      messageClass: 'map_point',
      payload: jsonEncode(point.toJson()),
    );
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
    return result;
  }

  Future<bool> receiveMapPoint({
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

  Future<void> close() => delivery.close();
}
