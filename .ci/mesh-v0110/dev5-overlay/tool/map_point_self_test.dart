import 'dart:convert';
import 'dart:io';

import '../lib/core/app_storage.dart';
import '../lib/core/delivery.dart';
import '../lib/core/messenger_core.dart';
import '../lib/core/models.dart';
import '../lib/platform/lan_transport.dart';

final class _AcceptedTransport implements MessageTransport {
  @override
  String get id => 'test';
  @override
  bool get isAvailable => true;
  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async =>
      const TransportSendResult(TransportSendStatus.accepted);
}

Future<void> main() async {
  final point = MapPoint(
    id: 'p-1',
    latitude: 54.3142,
    longitude: 48.4031,
    createdAt: DateTime.utc(2026, 9, 23, 12),
    label: 'Точка встречи',
    note: 'Вход с юга',
  );
  final raw = jsonEncode(point.toJson());
  final decoded = MapPoint.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  if (decoded.latitude != point.latitude ||
      decoded.longitude != point.longitude ||
      decoded.note != point.note) {
    throw StateError('MapPoint JSON round-trip failed');
  }

  final wire = LanWireCodec.data(
    messageId: 'm-map-1',
    fromMmId: 'mm:alpha123',
    toMmId: 'mm:beta456',
    messageClass: 'map_point',
    payload: raw,
  );
  final decodedWire = LanWireCodec.decode(wire);
  if (decodedWire == null ||
      decodedWire.kind != 'data' ||
      decodedWire.messageClass != 'map_point' ||
      decodedWire.payload != raw) {
    throw StateError('LAN MapPoint wire round-trip failed');
  }

  final rootA = await Directory.systemTemp.createTemp('mesh_map_a_');
  final rootB = await Directory.systemTemp.createTemp('mesh_map_b_');
  try {
    final coreA = MeshMessengerCore(
      ownMmId: 'mm:alpha123',
      storage: AppStorage(rootA),
      transports: [_AcceptedTransport()],
    );
    await coreA.restore();
    final sent = await coreA.sendMapPoint(peerMmId: 'mm:beta456', point: point);
    if (sent.messageClass != 'map_point' || sent.payload != raw) {
      throw StateError('MapPoint delivery envelope invalid');
    }
    final historyA = await coreA.messagesFor('mm:beta456');
    if (historyA.length != 1 || !historyA.single.isMapPoint) {
      throw StateError('Outgoing MapPoint history failed');
    }

    final coreB = MeshMessengerCore(
      ownMmId: 'mm:beta456',
      storage: AppStorage(rootB),
      transports: [_AcceptedTransport()],
    );
    await coreB.restore();
    final first = await coreB.receiveMapPoint(
      messageId: sent.messageId,
      fromMmId: 'mm:alpha123',
      payload: sent.payload,
    );
    final duplicate = await coreB.receiveMapPoint(
      messageId: sent.messageId,
      fromMmId: 'mm:alpha123',
      payload: sent.payload,
    );
    if (!first || duplicate) throw StateError('MapPoint dedup failed');
    final historyB = await coreB.messagesFor('mm:alpha123');
    if (historyB.length != 1 || historyB.single.mapPoint?.id != point.id) {
      throw StateError('Incoming MapPoint persistence failed');
    }
    await coreA.close();
    await coreB.close();
  } finally {
    await rootA.delete(recursive: true);
    await rootB.delete(recursive: true);
  }

  stdout.writeln('MESH_MESSENGER_MAP_POINT_SELF_TEST_PASS');
}
