import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'local_storage_crypto.dart';
import 'models.dart';

/// One small storage owner for the current prototype.
/// We can replace the JSON implementation later without changing chat/delivery logic.
final class AppIdentity {
  const AppIdentity({required this.mmId, required this.label});
  final String mmId;
  final String label;
}

final class AppStorage {
  AppStorage(
    this.root, {
    AppStorageCrypto? crypto,
    this.requireEncryption = false,
  }) : _crypto = crypto;

  static const _encryptedSchema = 'mesh-messenger-local-storage/v1';
  static const _contactsPurpose = 'contacts';
  static const _groupsPurpose = 'groups';
  static const _groupReceiptsPurpose = 'group_receipts';
  static const _messagesPurpose = 'messages';
  static const _outboxPurpose = 'outbox';

  final Directory root;
  final AppStorageCrypto? _crypto;
  final bool requireEncryption;
  Future<void> _mutationTail = Future<void>.value();

  File get _contactsFile => File('${root.path}/contacts.json');
  File get _messagesFile => File('${root.path}/messages.json');
  File get _groupsFile => File('${root.path}/groups.json');
  File get _groupReceiptsFile => File('${root.path}/group_receipts.json');
  File get _outboxFile => File('${root.path}/outbox.json');
  File get _identityFile => File('${root.path}/identity.json');
  File get _uiPreferencesFile => File('${root.path}/ui_preferences.json');

  Future<Map<String, dynamic>> loadUiPreferences() async {
    if (!await _uiPreferencesFile.exists()) return <String, dynamic>{};
    try {
      final raw = jsonDecode(await _uiPreferencesFile.readAsString());
      return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> saveUiPreferences(Map<String, Object?> values) =>
      _serialized(() async {
        await root.create(recursive: true);
        await _uiPreferencesFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(values),
          flush: true,
        );
      });

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
      (await _readList(
        _contactsFile,
        sensitivePurpose: _contactsPurpose,
      )).map(Contact.fromJson).toList();

  Future<void> saveContact(Contact contact) => _serialized(() async {
    final items = {
      for (final raw in await _readList(
        _contactsFile,
        sensitivePurpose: _contactsPurpose,
      ))
        Contact.fromJson(raw).mmId: Contact.fromJson(raw),
    };
    items[contact.mmId] = contact;
    await _writeList(
      _contactsFile,
      items.values.map((e) => e.toJson()).toList(),
      sensitivePurpose: _contactsPurpose,
    );
  });

  Future<List<GroupDefinition>> loadGroups() async =>
      (await _readList(
        _groupsFile,
        sensitivePurpose: _groupsPurpose,
      )).map(GroupDefinition.fromJson).toList();

  Future<void> saveGroup(GroupDefinition group) => _serialized(() async {
    final items = {
      for (final raw in await _readList(
        _groupsFile,
        sensitivePurpose: _groupsPurpose,
      ))
        GroupDefinition.fromJson(raw).groupId: GroupDefinition.fromJson(raw),
    };
    final current = items[group.groupId];
    if (current == null || group.revision >= current.revision) {
      items[group.groupId] = group;
    }
    await _writeList(
      _groupsFile,
      items.values.map((e) => e.toJson()).toList(),
      sensitivePurpose: _groupsPurpose,
    );
  });

  Future<List<GroupReceiptRecord>> loadGroupReceipts() async =>
      (await _readList(
        _groupReceiptsFile,
        sensitivePurpose: _groupReceiptsPurpose,
      ))
          .map(GroupReceiptRecord.fromJson)
          .toList();

  Future<void> saveGroupReceipt(GroupReceiptRecord receipt) =>
      _serialized(() async {
        final all = (await _readList(
          _groupReceiptsFile,
          sensitivePurpose: _groupReceiptsPurpose,
        ))
            .map(GroupReceiptRecord.fromJson)
            .toList();
        final exists = all.any(
          (item) =>
              item.messageId == receipt.messageId &&
              item.memberMmId == receipt.memberMmId,
        );
        if (!exists) {
          all.add(receipt);
          await _writeList(
            _groupReceiptsFile,
            all.map((e) => e.toJson()).toList(),
            sensitivePurpose: _groupReceiptsPurpose,
          );
        }
      });

  Future<List<ConversationMessage>> loadMessages({
    String? peerMmId,
    String? conversationKey,
  }) async {
    final all = (await _readList(
      _messagesFile,
      sensitivePurpose: _messagesPurpose,
    ))
        .map(ConversationMessage.fromJson)
        .toList();
    if (conversationKey != null) {
      return all
          .where((m) => m.effectiveConversationKey == conversationKey)
          .toList();
    }
    if (peerMmId == null) return all;
    return all.where((m) => m.peerMmId == peerMmId).toList();
  }

  Future<void> appendMessage(ConversationMessage message) async {
    await appendMessageUnique(message);
  }

  Future<bool> appendMessageUnique(ConversationMessage message) => _serialized(
    () async {
      final all = (await _readList(
        _messagesFile,
        sensitivePurpose: _messagesPurpose,
      ))
          .map(ConversationMessage.fromJson)
          .toList();
      if (all.any((item) => item.messageId == message.messageId)) return false;
      all.add(message);
      await _writeList(
        _messagesFile,
        all.map((e) => e.toJson()).toList(),
        sensitivePurpose: _messagesPurpose,
      );
      return true;
    },
  );

  Future<List<DeliveryEnvelope>> loadOutbox() async =>
      (await _readList(
        _outboxFile,
        sensitivePurpose: _outboxPurpose,
      )).map(DeliveryEnvelope.fromJson).toList();

  Future<void> saveOutboxItem(DeliveryEnvelope item) => _serialized(() async {
    final items = {
      for (final raw in await _readList(
        _outboxFile,
        sensitivePurpose: _outboxPurpose,
      ))
        DeliveryEnvelope.fromJson(raw).effectiveDeliveryId:
            DeliveryEnvelope.fromJson(raw),
    };
    items[item.messageId] = item;
    await _writeList(
      _outboxFile,
      items.values.map((e) => e.toJson()).toList(),
      sensitivePurpose: _outboxPurpose,
    );
  });

  Future<void> removeOutboxItem(String deliveryId) => _serialized(() async {
    final items = (await _readList(
      _outboxFile,
      sensitivePurpose: _outboxPurpose,
    ))
        .map(DeliveryEnvelope.fromJson)
        .where((e) => e.effectiveDeliveryId != deliveryId);
    await _writeList(
      _outboxFile,
      items.map((e) => e.toJson()).toList(),
      sensitivePurpose: _outboxPurpose,
    );
  });

  Future<void> migrateSensitiveStorage() => _serialized(() async {
    await _migrateSensitiveFile(_contactsFile, _contactsPurpose);
    await _migrateSensitiveFile(_groupsFile, _groupsPurpose);
    await _migrateSensitiveFile(_groupReceiptsFile, _groupReceiptsPurpose);
    await _migrateSensitiveFile(_messagesFile, _messagesPurpose);
    await _migrateSensitiveFile(_outboxFile, _outboxPurpose);
  });

  Future<void> _migrateSensitiveFile(File file, String purpose) async {
    File? source;
    if (await file.exists()) {
      source = file;
    } else {
      final backup = File('${file.path}.bak');
      if (await backup.exists()) source = backup;
    }
    if (source == null) return;

    final text = await source.readAsString();
    if (text.trim().isEmpty) return;
    final decoded = jsonDecode(text);
    if (_isEncryptedEnvelope(decoded)) return;
    if (decoded is! List) {
      throw FormatException('${file.path} has unsupported storage format');
    }
    if (_crypto == null) {
      if (requireEncryption) {
        throw StateError('LOCAL_STORAGE_ENCRYPTION_REQUIRED:$purpose');
      }
      return;
    }
    await _writeList(
      file,
      decoded.cast<Map<String, dynamic>>(),
      sensitivePurpose: purpose,
    );
  }

  Future<List<Map<String, dynamic>>> _readList(
    File file, {
    String? sensitivePurpose,
  }) async {
    File source = file;
    if (!await source.exists()) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) return [];
      source = backup;
    }
    final text = await source.readAsString();
    if (text.trim().isEmpty) return [];
    final decoded = jsonDecode(text);

    Object? clear = decoded;
    if (sensitivePurpose != null && _isEncryptedEnvelope(decoded)) {
      final envelope = Map<String, dynamic>.from(decoded as Map);
      final purpose = envelope['purpose'];
      if (purpose != sensitivePurpose) {
        throw const FormatException('LOCAL_STORAGE_PURPOSE_MISMATCH');
      }
      final crypto = _crypto;
      if (crypto == null) {
        throw StateError('LOCAL_STORAGE_CRYPTO_UNAVAILABLE:$sensitivePurpose');
      }
      final iv = envelope['iv'];
      final ciphertext = envelope['ciphertext'];
      if (iv is! String || ciphertext is! String) {
        throw const FormatException('LOCAL_STORAGE_ENVELOPE_INVALID');
      }
      final plaintext = await crypto.decrypt(
        purpose: sensitivePurpose,
        iv: iv,
        ciphertext: ciphertext,
      );
      clear = jsonDecode(plaintext);
    } else if (sensitivePurpose != null && requireEncryption && decoded is List) {
      throw StateError('LOCAL_STORAGE_PLAINTEXT_REQUIRES_MIGRATION:$sensitivePurpose');
    }

    if (clear is! List) {
      throw FormatException('${file.path} must contain a JSON list');
    }
    return clear.cast<Map<String, dynamic>>();
  }

  bool _isEncryptedEnvelope(Object? value) =>
      value is Map && value['schema'] == _encryptedSchema;

  Future<void> _writeList(
    File file,
    List<Map<String, Object?>> data, {
    String? sensitivePurpose,
  }) async {
    final clearText = const JsonEncoder.withIndent('  ').convert(data);
    String diskText = clearText;
    if (sensitivePurpose != null) {
      final crypto = _crypto;
      if (crypto == null) {
        if (requireEncryption) {
          throw StateError('LOCAL_STORAGE_ENCRYPTION_REQUIRED:$sensitivePurpose');
        }
      } else {
        final encrypted = await crypto.encrypt(
          purpose: sensitivePurpose,
          plaintext: clearText,
        );
        final purpose = encrypted['purpose'];
        final iv = encrypted['iv'];
        final ciphertext = encrypted['ciphertext'];
        if (purpose != sensitivePurpose ||
            iv == null ||
            iv.isEmpty ||
            ciphertext == null ||
            ciphertext.isEmpty) {
          throw const FormatException('LOCAL_STORAGE_ENCRYPT_RESULT_INVALID');
        }
        diskText = const JsonEncoder.withIndent('  ').convert({
          'schema': _encryptedSchema,
          'purpose': sensitivePurpose,
          'iv': iv,
          'ciphertext': ciphertext,
        });
      }
    }
    await _writeTextAtomically(file, diskText);
  }

  Future<void> _writeTextAtomically(File file, String text) async {
    await root.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await tmp.writeAsString(text, flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    // If the main file is already missing but a recovery .bak exists, keep
    // that backup until the new encrypted main file is durably renamed.
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
