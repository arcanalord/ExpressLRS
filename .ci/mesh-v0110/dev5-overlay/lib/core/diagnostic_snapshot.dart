import 'dart:convert';

final class DiagnosticSnapshot {
  const DiagnosticSnapshot._();

  static const Set<String> _blockedKeyFragments = <String>{
    'password',
    'secret',
    'private',
    'seed',
    'token',
    'keymaterial',
  };

  static Map<String, dynamic> build({
    required String appVersion,
    required String ownMmId,
    required String activeConversation,
    required Map<String, dynamic> transport,
    required Map<String, dynamic> counters,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'schema': 'mesh-messenger-diagnostics/v1',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': appVersion,
      'ownMmId': ownMmId,
      'activeConversation': activeConversation,
      'transport': _sanitizeMap(transport),
      'counters': _sanitizeMap(counters),
      'extra': _sanitizeMap(extra),
    };
  }

  static String encode(Map<String, dynamic> snapshot) =>
      const JsonEncoder.withIndent('  ').convert(_sanitizeMap(snapshot));

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      final normalized =
          entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (_blockedKeyFragments.any(normalized.contains)) continue;
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        result[entry.key] = _sanitizeMap(value);
      } else if (value is List) {
        result[entry.key] = value.map(_sanitizeValue).toList(growable: false);
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value is Map<String, dynamic>) return _sanitizeMap(value);
    if (value is List) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    return value;
  }
}
