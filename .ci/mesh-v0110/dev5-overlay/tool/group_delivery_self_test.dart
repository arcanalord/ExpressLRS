import 'dart:io';

import '../lib/core/app_storage.dart';
import '../lib/core/delivery.dart';
import '../lib/core/messenger_core.dart';
import '../lib/core/models.dart';

final class _AcceptedTransport implements MessageTransport {
  @override
  String get id => 'accepted-group-test';

  @override
  bool get isAvailable => true;

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async =>
      const TransportSendResult(TransportSendStatus.accepted);
}

Future<void> main() async {
  const own = 'mm:self';
  final root = await Directory.systemTemp.createTemp('mesh_group_delivery_');
  try {
    final storage = AppStorage(root);
    final core = MeshMessengerCore(
      ownMmId: own,
      storage: storage,
      transports: [_AcceptedTransport()],
    );
    await core.restore();

    final group = await core.createGroup(
      displayName: 'Field Team',
      memberMmIds: const ['mm:b', 'mm:c'],
    );
    if (ConversationRef.group(group.groupId).key != 'group:${group.groupId}') {
      throw StateError('Group conversation key mismatch');
    }
    if (group.memberMmIds.toSet().length != 3 ||
        !group.contains(own) ||
        !group.contains('mm:b') ||
        !group.contains('mm:c')) {
      throw StateError('Group membership invalid');
    }
    final storedGroups = await core.groups();
    if (storedGroups.length != 1 ||
        storedGroups.single.groupId != group.groupId) {
      throw StateError('Group persistence failed');
    }

    final legs = await core.sendGroupText(
      groupId: group.groupId,
      text: 'hello group',
    );
    if (legs.length != 2) throw StateError('Expected two delivery legs');
    final logicalIds = legs.map((e) => e.messageId).toSet();
    if (logicalIds.length != 1) {
      throw StateError('Group legs must share one logical messageId');
    }
    final deliveryIds = legs.map((e) => e.effectiveDeliveryId).toSet();
    if (deliveryIds.length != 2) {
      throw StateError('Group delivery legs need unique deliveryId');
    }
    if (legs.any((e) => !e.isGroup || e.state != DeliveryState.waitingAck)) {
      throw StateError('Group legs must wait for member receipts');
    }
    final members = legs.map((e) => e.groupMemberMmId).toSet();
    if (!members.containsAll(const ['mm:b', 'mm:c'])) {
      throw StateError('Group leg recipients invalid');
    }

    final messageId = legs.first.messageId;
    final history = await core.messagesForConversation(
      ConversationRef.group(group.groupId),
    );
    if (history.length != 1 ||
        history.single.messageId != messageId ||
        history.single.text != 'hello group') {
      throw StateError('Group history must contain one logical message');
    }

    final receipt = await core.receiveGroupReceipt(
      messageId: messageId,
      fromMmId: 'mm:b',
      groupId: group.groupId,
    );
    if (receipt?.state != DeliveryState.delivered) {
      throw StateError('Member receipt did not deliver its leg');
    }
    final afterReceipt = core.delivery.legsForMessage(messageId);
    if (afterReceipt.where((e) => e.state == DeliveryState.delivered).length !=
            1 ||
        afterReceipt.where((e) => e.state == DeliveryState.waitingAck).length !=
            1) {
      throw StateError('Per-member delivery state is not independent');
    }
    final persistedReceipts = await core.groupReceipts();
    if (persistedReceipts.length != 1 ||
        persistedReceipts.single.memberMmId != 'mm:b') {
      throw StateError('Group receipt persistence failed');
    }

    final incoming = await core.receiveGroupText(
      messageId: 'remote-group-1',
      fromMmId: 'mm:b',
      groupId: group.groupId,
      membershipRevision: group.revision,
      text: 'from b',
    );
    final duplicate = await core.receiveGroupText(
      messageId: 'remote-group-1',
      fromMmId: 'mm:b',
      groupId: group.groupId,
      membershipRevision: group.revision,
      text: 'from b',
    );
    if (!incoming || duplicate) throw StateError('Group dedupe failed');

    final outsider = await core.receiveGroupText(
      messageId: 'outsider-1',
      fromMmId: 'mm:outsider',
      groupId: group.groupId,
      membershipRevision: group.revision,
      text: 'bad',
    );
    if (outsider) throw StateError('Non-member group data must be rejected');

    final outsiderReceipt = await core.receiveGroupReceipt(
      messageId: messageId,
      fromMmId: 'mm:outsider',
      groupId: group.groupId,
    );
    if (outsiderReceipt != null) {
      throw StateError('Non-member receipt must be ignored');
    }

    final direct = await core.sendText(peerMmId: 'mm:b', text: 'direct');
    if (direct.state != DeliveryState.waitingAck || direct.isGroup) {
      throw StateError('Direct delivery semantics regressed');
    }
    final directAck = await core.acknowledge(direct.messageId, 'mm:b');
    if (directAck?.state != DeliveryState.delivered) {
      throw StateError('Direct ACK semantics regressed');
    }

    final general = await core.sendChannelText(
      channelId: 'general',
      text: 'general',
    );
    if (general.state != DeliveryState.broadcasted || !general.isChannel) {
      throw StateError('General channel semantics regressed');
    }

    await core.close();
  } finally {
    await root.delete(recursive: true);
  }

  stdout.writeln('MESH_MESSENGER_GROUP_DELIVERY_SELF_TEST_PASS');
}
