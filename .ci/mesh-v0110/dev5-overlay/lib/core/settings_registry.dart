enum SettingsOwner {
  shared,
  m03,
  lr24,
  meshtastic,
}

enum SettingValueType {
  boolean,
  integer,
  decimal,
  text,
  enumeration,
  secret,
}

enum SettingScope {
  device,
  module,
  transport,
}

final class FirmwareVersion implements Comparable<FirmwareVersion> {
  const FirmwareVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  factory FirmwareVersion.parse(String raw) {
    final clean = raw.trim().split(RegExp(r'[-+]')).first;
    final parts = clean.split('.');
    if (parts.length < 2) {
      throw FormatException('Invalid firmware version: $raw');
    }
    int part(int index) =>
        index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0;
    return FirmwareVersion(part(0), part(1), part(2));
  }

  @override
  int compareTo(FirmwareVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

final class SettingDefinition {
  const SettingDefinition({
    required this.id,
    required this.owner,
    required this.scope,
    required this.group,
    required this.fieldPath,
    required this.valueType,
    required this.label,
    this.description = '',
    this.minimum,
    this.maximum,
    this.enumValues = const [],
    this.supportedTransports = const {},
    this.sinceFirmware,
    this.untilFirmware,
    this.requiresCapability,
    this.secret = false,
  });

  final String id;
  final SettingsOwner owner;
  final SettingScope scope;
  final String group;
  final String fieldPath;
  final SettingValueType valueType;
  final String label;
  final String description;
  final num? minimum;
  final num? maximum;
  final List<String> enumValues;
  final Set<String> supportedTransports;
  final String? sinceFirmware;
  final String? untilFirmware;
  final String? requiresCapability;
  final bool secret;

  bool supports({
    required String transportId,
    String? firmwareVersion,
    Set<String> capabilities = const {},
  }) {
    if (supportedTransports.isNotEmpty &&
        !supportedTransports.contains(transportId)) {
      return false;
    }
    if (requiresCapability != null &&
        !capabilities.contains(requiresCapability)) {
      return false;
    }
    if (firmwareVersion == null) {
      return sinceFirmware == null && untilFirmware == null;
    }
    final current = FirmwareVersion.parse(firmwareVersion);
    if (sinceFirmware != null &&
        current.compareTo(FirmwareVersion.parse(sinceFirmware!)) < 0) {
      return false;
    }
    if (untilFirmware != null &&
        current.compareTo(FirmwareVersion.parse(untilFirmware!)) > 0) {
      return false;
    }
    return true;
  }

  bool validate(Object? value) {
    if (value == null) return false;
    switch (valueType) {
      case SettingValueType.boolean:
        return value is bool;
      case SettingValueType.integer:
        if (value is! int) return false;
        return _validateNumber(value);
      case SettingValueType.decimal:
        if (value is! num) return false;
        return _validateNumber(value);
      case SettingValueType.text:
      case SettingValueType.secret:
        return value is String;
      case SettingValueType.enumeration:
        return value is String && enumValues.contains(value);
    }
  }

  bool _validateNumber(num value) {
    if (minimum != null && value < minimum!) return false;
    if (maximum != null && value > maximum!) return false;
    return true;
  }
}

final class SettingsRegistry {
  const SettingsRegistry(this.definitions);

  final List<SettingDefinition> definitions;

  SettingDefinition? byId(String id) {
    for (final definition in definitions) {
      if (definition.id == id) return definition;
    }
    return null;
  }

  List<SettingDefinition> available({
    required String transportId,
    String? firmwareVersion,
    Set<String> capabilities = const {},
  }) => List.unmodifiable(
    definitions.where(
      (definition) => definition.supports(
        transportId: transportId,
        firmwareVersion: firmwareVersion,
        capabilities: capabilities,
      ),
    ),
  );
}

const _meshtasticTransport = 'meshtastic';
const _m03Transport = 'm03';
const _lr24Transport = 'lr24';

const settingsRegistry = SettingsRegistry([
  SettingDefinition(
    id: 'meshtastic.device.role',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'Device',
    fieldPath: 'config.device.role',
    valueType: SettingValueType.enumeration,
    label: 'Device role',
    enumValues: [
      'CLIENT',
      'CLIENT_MUTE',
      'ROUTER',
      'ROUTER_CLIENT',
      'REPEATER',
      'TRACKER',
      'SENSOR',
      'TAK',
      'CLIENT_HIDDEN',
      'LOST_AND_FOUND',
      'TAK_TRACKER',
    ],
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.position.broadcast_secs',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'Position',
    fieldPath: 'config.position.position_broadcast_secs',
    valueType: SettingValueType.integer,
    label: 'Position broadcast interval',
    minimum: 0,
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.power.saving',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'Power',
    fieldPath: 'config.power.is_power_saving',
    valueType: SettingValueType.boolean,
    label: 'Power saving',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.network.wifi_enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'Network',
    fieldPath: 'config.network.wifi_enabled',
    valueType: SettingValueType.boolean,
    label: 'Wi-Fi enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.lora.region',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'LoRa',
    fieldPath: 'config.lora.region',
    valueType: SettingValueType.enumeration,
    label: 'LoRa region',
    enumValues: [
      'UNSET',
      'US',
      'EU_433',
      'EU_868',
      'CN',
      'JP',
      'ANZ',
      'KR',
      'TW',
      'RU',
      'IN',
      'NZ_865',
      'TH',
      'LORA_24',
      'UA_433',
      'UA_868',
      'MY_433',
      'MY_919',
      'SG_923',
      'PH_433',
      'PH_868',
      'PH_915',
    ],
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.lora.tx_power',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'LoRa',
    fieldPath: 'config.lora.tx_power',
    valueType: SettingValueType.integer,
    label: 'TX power',
    minimum: 0,
    supportedTransports: {_meshtasticTransport},
    requiresCapability: 'tx_power_configurable',
  ),
  SettingDefinition(
    id: 'meshtastic.bluetooth.enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'Bluetooth',
    fieldPath: 'config.bluetooth.enabled',
    valueType: SettingValueType.boolean,
    label: 'Bluetooth enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.security.admin_channel_index',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.device,
    group: 'Security',
    fieldPath: 'config.security.admin_channel_index',
    valueType: SettingValueType.integer,
    label: 'Admin channel index',
    minimum: 0,
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.mqtt.enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'MQTT',
    fieldPath: 'module_config.mqtt.enabled',
    valueType: SettingValueType.boolean,
    label: 'MQTT enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.mqtt.address',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'MQTT',
    fieldPath: 'module_config.mqtt.address',
    valueType: SettingValueType.text,
    label: 'MQTT server',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.serial.enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'Serial',
    fieldPath: 'module_config.serial.enabled',
    valueType: SettingValueType.boolean,
    label: 'Serial module enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.external_notification.enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'External Notification',
    fieldPath: 'module_config.external_notification.enabled',
    valueType: SettingValueType.boolean,
    label: 'External notification enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.store_forward.enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'Store & Forward',
    fieldPath: 'module_config.store_forward.enabled',
    valueType: SettingValueType.boolean,
    label: 'Store and forward enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'meshtastic.telemetry.device_enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'Telemetry',
    fieldPath: 'module_config.telemetry.device_telemetry_enabled',
    valueType: SettingValueType.boolean,
    label: 'Broadcast device metrics',
    supportedTransports: {_meshtasticTransport},
    sinceFirmware: '2.7.13',
  ),
  SettingDefinition(
    id: 'meshtastic.neighbor_info.enabled',
    owner: SettingsOwner.meshtastic,
    scope: SettingScope.module,
    group: 'Neighbor Info',
    fieldPath: 'module_config.neighbor_info.enabled',
    valueType: SettingValueType.boolean,
    label: 'Neighbor info enabled',
    supportedTransports: {_meshtasticTransport},
  ),
  SettingDefinition(
    id: 'm03.radio.profile',
    owner: SettingsOwner.m03,
    scope: SettingScope.transport,
    group: 'Radio',
    fieldPath: 'm03.profile_id',
    valueType: SettingValueType.text,
    label: 'M03 radio profile',
    supportedTransports: {_m03Transport},
    requiresCapability: 'profile_select',
  ),
  SettingDefinition(
    id: 'lr24.uart.baud',
    owner: SettingsOwner.lr24,
    scope: SettingScope.transport,
    group: 'Radio',
    fieldPath: 'lr24.uart.baud',
    valueType: SettingValueType.enumeration,
    label: 'LR24 UART baud rate',
    enumValues: ['57600', '115200', '921600'],
    supportedTransports: {_lr24Transport},
  ),
]);
