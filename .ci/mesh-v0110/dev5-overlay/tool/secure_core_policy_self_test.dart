import 'dart:io';

import '../lib/core/secure_core_policy.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final dev = SecureCorePolicy.forBuild(isRelease: false);
  check(!dev.requirePrivateE2ee, 'dev should not require private E2EE');
  check(!dev.requireEncryptedStorage, 'dev should not require encrypted storage');
  check(!dev.isProductionLike, 'dev should not be production-like');

  final prod = SecureCorePolicy.forBuild(isRelease: true);
  check(prod.requirePrivateE2ee, 'production must require private E2EE');
  check(prod.requireEncryptedStorage, 'production must require encrypted storage');
  check(prod.isProductionLike, 'production should be production-like');

  check(SecureCorePolicy.highRisk.requirePrivateE2ee, 'high-risk E2EE required');
  check(
    SecureCorePolicy.highRisk.requireEncryptedStorage,
    'high-risk encrypted storage required',
  );

  stdout.writeln('SECURE_CORE_POLICY_PASS');
}
