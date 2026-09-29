abstract interface class AppStorageCrypto {
  Future<Map<String, String>> encrypt({
    required String purpose,
    required String plaintext,
  });

  Future<String> decrypt({
    required String purpose,
    required String iv,
    required String ciphertext,
  });
}
