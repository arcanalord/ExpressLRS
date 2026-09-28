import 'dart:convert';
import 'dart:io';

import '../lib/core/app_storage.dart';
import '../lib/core/local_storage_crypto.dart';
import '../lib/core/models.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

/// Test-only reversible codec. This validates AppStorage boundaries and
/// migration behavior; Android AES-GCM itself is compiled from
/// SecureStorageCipher.kt and is not reimplemented in Dart.
final class _TestStorageCrypto implements AppStorageCrypto {
  @override
  Future<Map<String, String>> encrypt({
    required String purpose,
    required String plaintext,
  }) async {
    final packed = utf8.encode('$purpose|${plaintext.split('').reversed.join()}');
    return <String, String>{
      'purpose': purpose,
      'iv': base64UrlEncode(utf8.encode('test-iv-$purpose')),
      'ciphertext': base64UrlEncode(packed),
    };
  }

  @override
  Future<String> decrypt({
    required String purpose,
    required String iv,
    required String ciphertext,
  }) async {
    final packed = utf8.decode(base64Url.decode(ciphertext));
    final prefix = '$purpose|';
    if (!packed.startsWith(prefix)) {
      throw StateError('test purpose authentication failed');
    }
    return packed.substring(prefix.length).split('').reversed.join();
  }
}

ConversationMessage _message(String id, String text) => ConversationMessage(
  messageId: id,
  peerMmId: 'mm:peer01',
  text: text,
  outgoing: true,
  createdAt: DateTime.utc(2026, 9, 28),
  conversationKey: 'direct:mm:peer01',
  senderMmId: 'mm:self01',
);

DeliveryEnvelope _outbox(String id, String payload) => DeliveryEnvelope(
  messageId: id,
  recipientMmId: 'mm:peer01',
  messageClass: 'text',
  payload: payload,
  createdAt: DateTime.utc(2026, 9, 28),
  expiresAt: DateTime.utc(2026, 9, 29),
  priority: 0,
  state: DeliveryState.queued,
);

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('mesh-storage-crypto-');
  final blockedRoot = Directory.systemTemp.createTempSync(
    'mesh-storage-blocked-',
  );
  final backupOnlyRoot = Directory.systemTemp.createTempSync(
    'mesh-storage-backup-only-',
  );
  try {
    const secret = 'TOP SECRET LOCAL MESSAGE';
    const pendingSecret = 'PENDING PRIVATE OUTBOX';
    const contactSecret = 'PRIVATE CONTACT ALICE';
    const groupSecret = 'PRIVATE GROUP ALPHA';

    final legacy = AppStorage(root);
    await legacy.saveContact(
      const Contact(
        mmId: 'mm:alice01',
        displayName: contactSecret,
        verified: true,
      ),
    );
    await legacy.saveGroup(
      GroupDefinition(
        groupId: 'g-private',
        displayName: groupSecret,
        creatorMmId: 'mm:self01',
        memberMmIds: const <String>['mm:self01', 'mm:alice01'],
        revision: 1,
        createdAt: DateTime.utc(2026, 9, 28),
        updatedAt: DateTime.utc(2026, 9, 28),
      ),
    );
    await legacy.saveGroupReceipt(
      GroupReceiptRecord(
        messageId: 'gm1',
        groupId: 'g-private',
        memberMmId: 'mm:alice01',
        receivedAt: DateTime.utc(2026, 9, 28),
      ),
    );
    await legacy.appendMessageUnique(_message('m1', secret));
    await legacy.saveOutboxItem(_outbox('o1', pendingSecret));

    final contactFile = File('${root.path}/contacts.json');
    final groupFile = File('${root.path}/groups.json');
    final receiptFile = File('${root.path}/group_receipts.json');
    final messageFile = File('${root.path}/messages.json');
    final outboxFile = File('${root.path}/outbox.json');
    check(
      (await contactFile.readAsString()).contains(contactSecret),
      'legacy contact fixture must start as plaintext',
    );
    check(
      (await groupFile.readAsString()).contains(groupSecret),
      'legacy group fixture must start as plaintext',
    );
    check(
      (await receiptFile.readAsString()).contains('mm:alice01'),
      'legacy receipt fixture must start as plaintext',
    );
    check(
      (await messageFile.readAsString()).contains(secret),
      'legacy fixture must start as plaintext',
    );
    check(
      (await outboxFile.readAsString()).contains(pendingSecret),
      'legacy outbox fixture must start as plaintext',
    );

    final secure = AppStorage(
      root,
      crypto: _TestStorageCrypto(),
      requireEncryption: true,
    );
    await secure.migrateSensitiveStorage();

    final encryptedContacts = await contactFile.readAsString();
    final encryptedGroups = await groupFile.readAsString();
    final encryptedReceipts = await receiptFile.readAsString();
    final encryptedMessages = await messageFile.readAsString();
    final encryptedOutbox = await outboxFile.readAsString();
    check(!encryptedContacts.contains(contactSecret), 'contact graph plaintext remains on disk');
    check(!encryptedGroups.contains(groupSecret), 'group metadata plaintext remains on disk');
    check(!encryptedReceipts.contains('mm:alice01'), 'group receipt metadata remains on disk');
    check(!encryptedMessages.contains(secret), 'messages plaintext remains on disk');
    check(
      !encryptedOutbox.contains(pendingSecret),
      'outbox plaintext remains on disk',
    );
    check(
      encryptedMessages.contains('mesh-messenger-local-storage/v1'),
      'messages encrypted envelope missing',
    );
    check(
      encryptedOutbox.contains('mesh-messenger-local-storage/v1'),
      'outbox encrypted envelope missing',
    );

    final restoredContacts = await secure.loadContacts();
    final restoredGroups = await secure.loadGroups();
    final restoredReceipts = await secure.loadGroupReceipts();
    final restoredMessages = await secure.loadMessages(peerMmId: 'mm:peer01');
    final restoredOutbox = await secure.loadOutbox();
    check(
      restoredContacts.length == 1 &&
          restoredContacts.single.displayName == contactSecret,
      'encrypted contact restart/readback failed',
    );
    check(
      restoredGroups.length == 1 &&
          restoredGroups.single.displayName == groupSecret,
      'encrypted group restart/readback failed',
    );
    check(
      restoredReceipts.length == 1 &&
          restoredReceipts.single.memberMmId == 'mm:alice01',
      'encrypted receipt restart/readback failed',
    );
    check(
      restoredMessages.length == 1 && restoredMessages.single.text == secret,
      'encrypted message restart/readback failed',
    );
    check(
      restoredOutbox.length == 1 &&
          restoredOutbox.single.payload == pendingSecret,
      'encrypted outbox restart/readback failed',
    );

    await secure.appendMessageUnique(_message('m2', 'SECOND PRIVATE MESSAGE'));
    check(
      !(await messageFile.readAsString()).contains('SECOND PRIVATE MESSAGE'),
      'new message write leaked plaintext',
    );

    final messageEnvelope = await messageFile.readAsString();
    await outboxFile.writeAsString(messageEnvelope, flush: true);
    var purposeRejected = false;
    try {
      await secure.loadOutbox();
    } catch (_) {
      purposeRejected = true;
    }
    check(purposeRejected, 'cross-store ciphertext purpose was accepted');

    final blocked = AppStorage(blockedRoot, requireEncryption: true);
    var missingCryptoRejected = false;
    try {
      await blocked.appendMessageUnique(_message('blocked', 'must not persist'));
    } catch (_) {
      missingCryptoRejected = true;
    }
    check(missingCryptoRejected, 'release policy wrote plaintext without crypto');
    check(
      !File('${blockedRoot.path}/messages.json').existsSync(),
      'failed secure write left a plaintext messages file',
    );

    const backupSecret = 'RECOVERED FROM BACKUP ONLY';
    final backupOnlyLegacy = AppStorage(backupOnlyRoot);
    await backupOnlyLegacy.appendMessageUnique(
      _message('backup-only', backupSecret),
    );
    final backupMain = File('${backupOnlyRoot.path}/messages.json');
    final backupFile = File('${backupOnlyRoot.path}/messages.json.bak');
    await backupMain.rename(backupFile.path);
    check(!backupMain.existsSync() && backupFile.existsSync(),
        'backup-only fixture not created');

    final backupOnlySecure = AppStorage(
      backupOnlyRoot,
      crypto: _TestStorageCrypto(),
      requireEncryption: true,
    );
    await backupOnlySecure.migrateSensitiveStorage();
    check(backupMain.existsSync(), 'encrypted main not restored from backup-only state');
    check(!backupFile.existsSync(), 'backup should be removed only after successful migration');
    final migratedBackupText = await backupMain.readAsString();
    check(!migratedBackupText.contains(backupSecret),
        'backup-only migration leaked plaintext into main');
    final recovered = await backupOnlySecure.loadMessages();
    check(recovered.length == 1 && recovered.single.text == backupSecret,
        'backup-only encrypted migration did not preserve message');

    stdout.writeln('LOCAL_STORAGE_ENCRYPTION_SELF_TEST_PASS');
  } finally {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (blockedRoot.existsSync()) blockedRoot.deleteSync(recursive: true);
    if (backupOnlyRoot.existsSync()) backupOnlyRoot.deleteSync(recursive: true);
  }
}
