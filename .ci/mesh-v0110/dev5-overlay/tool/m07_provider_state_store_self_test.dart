import 'dart:convert';
import 'dart:io';

import '../lib/core/local_storage_crypto.dart';
import '../lib/core/m07_provider_state_store.dart';
import '../lib/core/m07_security.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final class _FakeCrypto implements AppStorageCrypto {
  @override
  Future<Map<String, String>> encrypt({
    required String purpose,
    required String plaintext,
  }) async => <String, String>{
    'purpose': purpose,
    'iv': 'iv-$purpose',
    'ciphertext': base64UrlEncode(utf8.encode(plaintext)),
  };

  @override
  Future<String> decrypt({
    required String purpose,
    required String iv,
    required String ciphertext,
  }) async => utf8.decode(base64Url.decode(ciphertext));
}

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('m07-provider-store-');
  try {
    final store = M07ProviderStateStore(
      root: root,
      crypto: _FakeCrypto(),
    );

    final initial = await store.load();
    check(initial.generation == 0, 'empty store must start at generation 0');

    final outbound = M07AtomicOutboundCommit(
      commitId: 'out-1',
      envelope: EncryptedApplicationEnvelope(
        formatVersion: 1,
        suiteId: 'test-suite',
        ciphertextBase64: 'AQID',
      ),
      recoveryContextJson: '{"kind":"direct_text_out"}',
    );

    await store.transaction<void>((current) async {
      return M07ProviderTransactionResult<void>(
        next: current.next(
          providerOpaqueJson: '{"account":"pickle-a","sessions":{"mm:b":"pickle-s"}}',
          outboundCommits: <M07AtomicOutboundCommit>[outbound],
        ),
        value: null,
      );
    });

    final loaded = await store.load();
    check(loaded.generation == 1, 'generation must advance');
    check(
      loaded.providerOpaqueJson.contains('pickle-a'),
      'provider opaque state must roundtrip',
    );
    check(loaded.outboundCommits.length == 1, 'outbound journal must roundtrip');

    final file = File('${root.path}/m07_provider_state.json');
    final disk = await file.readAsString();
    check(!disk.contains('pickle-a'), 'provider state must not be plaintext at rest');
    check(!disk.contains('direct_text_out'), 'recovery journal must not be plaintext at rest');

    final inbound = M07AtomicInboundCommit(
      commitId: 'in-1',
      plaintext: DirectPlaintext(
        logicalMessageId: 'm1',
        senderMmId: 'mm:b',
        recipientMmId: 'mm:a',
        conversationKey: m07DirectSecurityContext('mm:a', 'mm:b'),
        messageClass: 'text',
        payloadUtf8: 'secret',
      ),
      recoveryContextJson: '{"kind":"direct_in"}',
    );

    await store.transaction<void>((current) async {
      return M07ProviderTransactionResult<void>(
        next: current.next(
          providerOpaqueJson: '{"account":"pickle-b"}',
          outboundCommits: const <M07AtomicOutboundCommit>[],
          inboundCommits: <M07AtomicInboundCommit>[inbound],
        ),
        value: null,
      );
    });

    final second = await store.load();
    check(second.generation == 2, 'second transaction must advance generation');
    check(second.outboundCommits.isEmpty, 'outbound journal must clear');
    check(second.inboundCommits.single.plaintext.payloadUtf8 == 'secret',
        'inbound recovery plaintext must roundtrip inside encrypted state');

    var rejected = false;
    try {
      await store.transaction<void>((current) async =>
          M07ProviderTransactionResult<void>(next: current, value: null));
    } on StateError {
      rejected = true;
    }
    check(rejected, 'non-advancing transaction must fail closed');

    print('M07_PROVIDER_STATE_STORE_PASS');
  } finally {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
