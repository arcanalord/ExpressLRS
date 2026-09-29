enum SecureCoreMode {
  development,
  production,
  highRisk,
}

/// Small policy object shared by application wiring.
///
/// Keep this deliberately narrow: it decides whether private E2EE and
/// encrypted local storage are mandatory. Crypto/storage implementations stay
/// behind their existing provider interfaces.
final class SecureCorePolicy {
  const SecureCorePolicy._({
    required this.mode,
    required this.requirePrivateE2ee,
    required this.requireEncryptedStorage,
  });

  static const development = SecureCorePolicy._(
    mode: SecureCoreMode.development,
    requirePrivateE2ee: false,
    requireEncryptedStorage: false,
  );

  static const production = SecureCorePolicy._(
    mode: SecureCoreMode.production,
    requirePrivateE2ee: true,
    requireEncryptedStorage: true,
  );

  static const highRisk = SecureCorePolicy._(
    mode: SecureCoreMode.highRisk,
    requirePrivateE2ee: true,
    requireEncryptedStorage: true,
  );

  factory SecureCorePolicy.forBuild({required bool isRelease}) =>
      isRelease ? production : development;

  final SecureCoreMode mode;
  final bool requirePrivateE2ee;
  final bool requireEncryptedStorage;

  bool get isProductionLike => mode != SecureCoreMode.development;
}
