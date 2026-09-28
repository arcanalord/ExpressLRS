import 'package:flutter/services.dart';

import '../core/local_storage_crypto.dart';

final class AndroidAppStorageCrypto implements AppStorageCrypto {
  AndroidAppStorageCrypto({
    MethodChannel? channel,
  }) : _channel =
           channel ?? const MethodChannel('org.fpvclub.mesh/securestorage');

  final MethodChannel _channel;

  @override
  Future<Map<String, String>> encrypt({
    required String purpose,
    required String plaintext,
  }) async {
    final raw = await _channel.invokeMethod<Object?>(
      'encrypt',
      <String, Object?>{
        'purpose': purpose,
        'plaintext': plaintext,
      },
    );
    if (raw is! Map) {
      throw const PlatformException(
        code: 'SECURE_STORAGE_FORMAT',
        message: 'encrypt result must be a map',
      );
    }
    final map = raw.map((key, value) => MapEntry('$key', '$value'));
    if (map['purpose'] != purpose ||
        (map['iv'] ?? '').isEmpty ||
        (map['ciphertext'] ?? '').isEmpty) {
      throw const PlatformException(
        code: 'SECURE_STORAGE_FORMAT',
        message: 'encrypt result is incomplete',
      );
    }
    return map;
  }

  @override
  Future<String> decrypt({
    required String purpose,
    required String iv,
    required String ciphertext,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'decrypt',
      <String, Object?>{
        'purpose': purpose,
        'iv': iv,
        'ciphertext': ciphertext,
      },
    );
    if (result == null) {
      throw const PlatformException(
        code: 'SECURE_STORAGE_FORMAT',
        message: 'decrypt result is null',
      );
    }
    return result;
  }
}
