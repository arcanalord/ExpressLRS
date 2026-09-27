import '../core/settings_registry.dart';

typedef JsonMap = Map<String, dynamic>;

final class MeshtasticConfigSnapshot {
  MeshtasticConfigSnapshot({
    required JsonMap config,
    required JsonMap moduleConfig,
    this.firmwareVersion,
  })  : config = _deepCopyMap(config),
        moduleConfig = _deepCopyMap(moduleConfig);

  final JsonMap config;
  final JsonMap moduleConfig;
  final String? firmwareVersion;

  MeshtasticConfigSnapshot copy() => MeshtasticConfigSnapshot(
        config: config,
        moduleConfig: moduleConfig,
        firmwareVersion: firmwareVersion,
      );
}

final class MeshtasticConfigAdapter {
  const MeshtasticConfigAdapter({
    this.registry = settingsRegistry,
  });

  final SettingsRegistry registry;

  Object? read(
    MeshtasticConfigSnapshot snapshot,
    String settingId, {
    Set<String> capabilities = const {},
  }) {
    final definition = _definition(settingId, snapshot, capabilities);
    final root = _rootFor(definition, snapshot);
    return _readPath(root, _relativePath(definition.fieldPath));
  }

  MeshtasticConfigSnapshot patch(
    MeshtasticConfigSnapshot snapshot,
    Map<String, Object?> changes, {
    Set<String> capabilities = const {},
  }) {
    final next = snapshot.copy();
    for (final entry in changes.entries) {
      final definition = _definition(entry.key, snapshot, capabilities);
      if (!definition.validate(entry.value)) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Value is not valid for ${definition.fieldPath}',
        );
      }
      final root = _rootFor(definition, next);
      _writePath(root, _relativePath(definition.fieldPath), entry.value);
    }
    return next;
  }

  Map<String, Object?> readAvailable(
    MeshtasticConfigSnapshot snapshot, {
    Set<String> capabilities = const {},
  }) {
    final result = <String, Object?>{};
    for (final definition in registry.available(
      transportId: 'meshtastic',
      firmwareVersion: snapshot.firmwareVersion,
      capabilities: capabilities,
    )) {
      if (definition.owner != SettingsOwner.meshtastic) continue;
      final value = read(
        snapshot,
        definition.id,
        capabilities: capabilities,
      );
      if (value != null) result[definition.id] = value;
    }
    return Map.unmodifiable(result);
  }

  SettingDefinition _definition(
    String settingId,
    MeshtasticConfigSnapshot snapshot,
    Set<String> capabilities,
  ) {
    final definition = registry.byId(settingId);
    if (definition == null || definition.owner != SettingsOwner.meshtastic) {
      throw ArgumentError.value(
        settingId,
        'settingId',
        'Unknown Meshtastic setting',
      );
    }
    if (!definition.supports(
      transportId: 'meshtastic',
      firmwareVersion: snapshot.firmwareVersion,
      capabilities: capabilities,
    )) {
      throw StateError(
        'Setting $settingId is not supported by firmware/capabilities',
      );
    }
    return definition;
  }

  JsonMap _rootFor(
    SettingDefinition definition,
    MeshtasticConfigSnapshot snapshot,
  ) {
    if (definition.fieldPath.startsWith('config.')) return snapshot.config;
    if (definition.fieldPath.startsWith('module_config.')) {
      return snapshot.moduleConfig;
    }
    throw StateError(
      'Unsupported Meshtastic field root: ${definition.fieldPath}',
    );
  }

  List<String> _relativePath(String fieldPath) {
    final parts = fieldPath.split('.');
    if (parts.length < 2) {
      throw StateError('Invalid field path: $fieldPath');
    }
    return parts.sublist(1);
  }
}

Object? _readPath(JsonMap root, List<String> path) {
  Object? cursor = root;
  for (final segment in path) {
    if (cursor is! Map) return null;
    cursor = cursor[segment];
  }
  return cursor;
}

void _writePath(JsonMap root, List<String> path, Object? value) {
  if (path.isEmpty) throw ArgumentError('Path is empty');
  JsonMap cursor = root;
  for (final segment in path.take(path.length - 1)) {
    final current = cursor[segment];
    if (current is Map<String, dynamic>) {
      cursor = current;
    } else if (current is Map) {
      final converted = current.cast<String, dynamic>();
      cursor[segment] = converted;
      cursor = converted;
    } else {
      final created = <String, dynamic>{};
      cursor[segment] = created;
      cursor = created;
    }
  }
  cursor[path.last] = _deepCopyValue(value);
}

JsonMap _deepCopyMap(Map<dynamic, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    result['${entry.key}'] = _deepCopyValue(entry.value);
  }
  return result;
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) return _deepCopyMap(value);
  if (value is List) return value.map(_deepCopyValue).toList();
  return value;
}
