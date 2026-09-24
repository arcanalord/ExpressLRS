import 'dart:io';

import '../lib/core/app_storage.dart';
import '../lib/core/models.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('mesh_storage_race_');
  try {
    final storage = AppStorage(root);
    final now = DateTime.utc(2026, 9, 23, 12);
    await Future.wait([
      for (var i = 0; i < 80; i++)
        storage.appendMessageUnique(
          ConversationMessage(
            messageId: 'm-$i',
            peerMmId: 'mm:peer123',
            text: 'message $i',
            outgoing: i.isEven,
            createdAt: now.add(Duration(milliseconds: i)),
          ),
        ),
    ]);
    final history = await storage.loadMessages(peerMmId: 'mm:peer123');
    if (history.length != 80) {
      throw StateError(
        'Concurrent message writes lost data: ${history.length}/80',
      );
    }

    final same = ConversationMessage(
      messageId: 'same-id',
      peerMmId: 'mm:peer123',
      text: 'same',
      outgoing: false,
      createdAt: now,
    );
    final results = await Future.wait([
      for (var i = 0; i < 20; i++) storage.appendMessageUnique(same),
    ]);
    if (results.where((value) => value).length != 1) {
      throw StateError('Persistent dedup race failed');
    }
    final after = await storage.loadMessages(peerMmId: 'mm:peer123');
    if (after.where((item) => item.messageId == 'same-id').length != 1) {
      throw StateError('Duplicate message persisted');
    }

    final envelope = DeliveryEnvelope(
      messageId: 'outbox-race',
      recipientMmId: 'mm:peer123',
      messageClass: 'text',
      payload: 'hello',
      createdAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      priority: 0,
      state: DeliveryState.queued,
    );
    await Future.wait([
      for (var i = 0; i < 40; i++) storage.saveOutboxItem(envelope),
    ]);
    if ((await storage.loadOutbox()).length != 1) {
      throw StateError('Outbox serialization failed');
    }
  } finally {
    await root.delete(recursive: true);
  }
  stdout.writeln('MESH_MESSENGER_STORAGE_CONCURRENCY_SELF_TEST_PASS');
}
