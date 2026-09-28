import 'dart:convert';
import 'dart:io';

import '../lib/core/app_storage.dart';
import '../lib/core/delivery.dart';
import '../lib/core/messenger_core.dart';
import '../lib/core/models.dart';

final class _AcceptedTransport implements MessageTransport {
  @override
  String get id => 'accepted-test';

  @override
  bool get isAvailable => true;

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async =>
      const TransportSendResult(TransportSendStatus.accepted);
}

Future<void> main() async {
  const general = ConversationRef.channel('general');
  if (general.key != 'channel:general') {
    throw StateError('General conversation key mismatch');
  }

  final legacy = ConversationMessage.fromJson({
    'messageId': 'legacy-1',
    'peerMmId': 'mm:legacy',
    'text': 'old',
    'outgoing': false,
    'createdAt': DateTime.utc(2026, 9, 27).toIso8601String(),
  });
  if (legacy.effectiveConversationKey != 'direct:mm:legacy') {
    throw StateError('Legacy direct migration failed');
  }

  final root = await Directory.systemTemp.createTemp('mesh_general_channel_');
  try {
    final storage = AppStorage(root);
    final core = MeshMessengerCore(
      ownMmId: 'mm:self',
      storage: storage,
      transports: [_AcceptedTransport()],
    );
    await core.restore();

    final sent = await core.sendChannelText(
      channelId: 'general',
      text: 'hello everyone',
    );
    if (!sent.isChannel ||
        sent.channelId != 'general' ||
        sent.state != DeliveryState.broadcasted) {
      throw StateError('Channel delivery envelope invalid: ${sent.state}');
    }

    final ownHistory = await core.messagesForConversation(general);
    if (ownHistory.length != 1 ||
        ownHistory.single.effectiveConversationKey != 'channel:general' ||
        ownHistory.single.senderMmId != 'mm:self') {
      throw StateError('Outgoing channel history invalid');
    }

    final outgoingPoint = MapPoint(
      id: 'general-point-out',
      latitude: 48.123,
      longitude: 11.456,
      createdAt: DateTime.utc(2026, 9, 28),
      label: 'meeting',
    );
    final sentPoint = await core.sendChannelMapPoint(
      channelId: 'general',
      point: outgoingPoint,
    );
    if (!sentPoint.isChannel ||
        sentPoint.channelId != 'general' ||
        sentPoint.messageClass != 'map_point' ||
        sentPoint.state != DeliveryState.broadcasted) {
      throw StateError('Channel MapPoint delivery invalid: ${sentPoint.state}');
    }

    final first = await core.receiveChannelText(
      messageId: 'remote-1',
      fromMmId: 'mm:unknown-peer',
      channelId: 'general',
      text: 'remote hello',
    );
    final duplicate = await core.receiveChannelText(
      messageId: 'remote-1',
      fromMmId: 'mm:unknown-peer',
      channelId: 'general',
      text: 'remote hello',
    );
    if (!first || duplicate) {
      throw StateError('Channel dedupe failed');
    }

    final remotePoint = MapPoint(
      id: 'general-point-in',
      latitude: 50.321,
      longitude: 8.765,
      createdAt: DateTime.utc(2026, 9, 28, 12),
      label: 'remote point',
    );
    final firstPoint = await core.receiveChannelMapPoint(
      messageId: 'remote-point-1',
      fromMmId: 'mm:unknown-peer',
      channelId: 'general',
      payload: jsonEncode(remotePoint.toJson()),
    );
    final duplicatePoint = await core.receiveChannelMapPoint(
      messageId: 'remote-point-1',
      fromMmId: 'mm:unknown-peer',
      channelId: 'general',
      payload: jsonEncode(remotePoint.toJson()),
    );
    if (!firstPoint || duplicatePoint) {
      throw StateError('Channel MapPoint dedupe failed');
    }

    final history = await core.messagesForConversation(general);
    if (history.length != 4) {
      throw StateError('General history count mismatch: ${history.length}');
    }
    final incoming = history
        .where((m) => !m.outgoing && m.messageClass == 'text')
        .single;
    if (incoming.senderMmId != 'mm:unknown-peer' ||
        incoming.peerMmId != 'channel:general') {
      throw StateError('Unknown channel sender metadata lost');
    }
    final incomingPoint = history
        .where((m) => !m.outgoing && m.messageClass == 'map_point')
        .single;
    if (incomingPoint.mapPoint?.id != 'general-point-in' ||
        incomingPoint.effectiveConversationKey != 'channel:general') {
      throw StateError('Incoming channel MapPoint metadata lost');
    }

    if ((await core.contacts()).isNotEmpty) {
      throw StateError('Unknown channel peer must not become a contact');
    }

    final direct = await core.sendText(
      peerMmId: 'mm:direct-peer',
      text: 'private',
    );
    if (direct.isChannel || direct.state != DeliveryState.waitingAck) {
      throw StateError('Direct delivery semantics regressed');
    }

    final directAck = await core.acknowledge(direct.messageId, 'mm:direct-peer');
    if (directAck?.state != DeliveryState.delivered) {
      throw StateError('Direct ACK semantics regressed');
    }

    await core.close();
  } finally {
    await root.delete(recursive: true);
  }

  stdout.writeln('MESH_MESSENGER_GENERAL_CHANNEL_SELF_TEST_PASS');
}
