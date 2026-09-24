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
  Future<List<ConversationMessage>> messagesFor(String peerMmId) =>
      _storage.loadMessages(peerMmId: peerMmId);
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
      ),
    );
    return result;
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
    ),
  );

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
  }) => delivery.recipientResult(
    messageId: messageId,
    fromMmId: fromMmId,
    ok: ok,
    detail: detail,
  );

  Future<void> close() => delivery.close();
}
