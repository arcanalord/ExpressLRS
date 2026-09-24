import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'models.dart';

/// One small storage owner for the current prototype.
/// We can replace the JSON implementation later without changing chat/delivery logic.
final class AppIdentity {
  const AppIdentity({required this.mmId, required this.label});
  final String mmId;
  final String label;
}

final class AppStorage {
  AppStorage(this.root);
  final Directory root;
  Future<void> _mutationTail = Future<void>.value();

  File get _contactsFile => File('${root.path}/contacts.json');
  File get _messagesFile => File('${root.path}/messages.json');
  File get _outboxFile => File('${root.path}/outbox.json');
  File get _identityFile => File('${root.path}/identity.json');

  Future<AppIdentity> loadOrCreateIdentity() async {
    if (await _identityFile.exists()) {
      try {
        final raw = jsonDecode(await _identityFile.readAsString());
        if (raw is Map<String, dynamic>) {
          final mmId = raw['mmId'];
          final label = raw['label'];
          if (mmId is String &&
              mmId.startsWith('mm:') &&
              label is String &&
              label.trim().isNotEmpty) {
            return AppIdentity(mmId: mmId, label: label);
          }
        }
      } catch (_) {}
    }
    final random = Random.secure();
    final hex = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final identity = AppIdentity(
      mmId: 'mm:$hex',
      label: 'Mesh-${hex.substring(hex.length - 6).toUpperCase()}',
    );
    await root.create(recursive: true);
    await _identityFile.writeAsString(
      const JsonEncoder.withIndent(' ')
          .convert({'mmId': identity.mmId, 'label': identity.label}),
      flush: true,
    );
    return identity;
  }

  Future<void> savePublicIdentityMetadata({
    required String mmId,
    required String label,
    required String fingerprint,
    required String identityPublicKey,
    required String agreementPublicKey,
    required String seedStorage,
  }) async {
    await root.create(recursive: true);
    await _identityFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'mmId': mmId,
        'label': label,
        'fingerprint': fingerprint,
        'identityPublicKey': identityPublicKey,
        'agreementPublicKey': agreementPublicKey,
        'seedStorage': seedStorage,
      }),
      flush: true,
    );
  }

  Future<List<Contact>> loadContacts() async =>
      (await _readList(_contactsFile)).map(Contact.fromJson).toList();

  Future<void> saveContact(Contact contact) => _serialized(() async {
    final items = {
      for (final raw in await _readList(_contactsFile))
        Contact.fromJson(raw).mmId: Contact.fromJson(raw),
    };
    items[contact.mmId] = contact;
    await _writeList(
      _contactsFile,
      items.values.map((e) => e.toJson()).toList(),
    );
  });

  Future<List<ConversationMessage>> loadMessages({String? peerMmId}) async {
    final all = (await _readList(_messagesFile))
        .map(ConversationMessage.fromJson)
        .toList();
    if (peerMmId == null) return all;
    return all.where((m) => m.peerMmId == peerMmId).toList();
  }

  Future<void> appendMessage(ConversationMessage message) async {
    await appendMessageUnique(message);
  }

  Future<bool> appendMessageUnique(ConversationMessage message) => _serialized(
    () async {
      final all = (await _readList(_messagesFile))
          .map(ConversationMessage.fromJson)
          .toList();
      if (all.any((item) => item.messageId == message.messageId)) return false;
      all.add(message);
      await _writeList(_messagesFile, all.map((e) => e.toJson()).toList());
      return true;
    },
  );

  Future<List<DeliveryEnvelope>> loadOutbox() async =>
      (await _readList(_outboxFile)).map(DeliveryEnvelope.fromJson).toList();

  Future<void> saveOutboxItem(DeliveryEnvelope item) => _serialized(() async {
    final items = {
      for (final raw in await _readList(_outboxFile))
        DeliveryEnvelope.fromJson(raw).messageId: DeliveryEnvelope.fromJson(
          raw,
        ),
    };
    items[item.messageId] = item;
    await _writeList(_outboxFile, items.values.map((e) => e.toJson()).toList());
  });

  Future<void> removeOutboxItem(String messageId) => _serialized(() async {
    final items = (await _readList(_outboxFile))
        .map(DeliveryEnvelope.fromJson)
        .where((e) => e.messageId != messageId);
    await _writeList(_outboxFile, items.map((e) => e.toJson()).toList());
  });

  Future<List<Map<String, dynamic>>> _readList(File file) async {
    File source = file;
    if (!await source.exists()) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) return [];
      source = backup;
    }
    final text = await source.readAsString();
    if (text.trim().isEmpty) return [];
    final decoded = jsonDecode(text);
    if (decoded is! List)
      throw FormatException('${file.path} must contain a JSON list');
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> _writeList(File file, List<Map<String, Object?>> data) async {
    await root.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await tmp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    })();
  }
}
