final class MeshAppBuildInfo {
  const MeshAppBuildInfo._();

  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.6.0-secure-core-rc8',
  );

  static const String build = String.fromEnvironment(
    'APP_BUILD',
    defaultValue: '26102109',
  );

  static const String display = '$version ($build)';
}
