import '../lib/core/settings_registry.dart';

void main() {
  final telemetry = settingsRegistry.byId('meshtastic.telemetry.device_enabled');
  if (telemetry == null) throw StateError('telemetry setting missing');
  if (telemetry.supports(
    transportId: 'meshtastic',
    firmwareVersion: '2.7.12',
  )) {
    throw StateError('firmware gate failed');
  }
  if (!telemetry.supports(
    transportId: 'meshtastic',
    firmwareVersion: '2.7.13',
  )) {
    throw StateError('since_firmware gate failed');
  }

  final txPower = settingsRegistry.byId('meshtastic.lora.tx_power');
  if (txPower == null) throw StateError('tx power setting missing');
  if (txPower.supports(
    transportId: 'meshtastic',
    firmwareVersion: '2.7.13',
  )) {
    throw StateError('capability gate failed');
  }
  if (!txPower.supports(
    transportId: 'meshtastic',
    firmwareVersion: '2.7.13',
    capabilities: {'tx_power_configurable'},
  )) {
    throw StateError('capability enable failed');
  }
  if (!txPower.validate(10) || txPower.validate(-1)) {
    throw StateError('numeric validation failed');
  }

  final mqtt = settingsRegistry.byId('meshtastic.mqtt.enabled');
  if (mqtt == null || !mqtt.validate(true) || mqtt.validate('yes')) {
    throw StateError('boolean validation failed');
  }

  final lr24 = settingsRegistry.available(
    transportId: 'lr24',
    firmwareVersion: '1.0.0',
  );
  if (lr24.any((setting) => setting.owner == SettingsOwner.meshtastic)) {
    throw StateError('transport isolation failed');
  }

  final meshtastic = settingsRegistry.available(
    transportId: 'meshtastic',
    firmwareVersion: '2.7.13',
    capabilities: {'tx_power_configurable'},
  );
  if (meshtastic.isEmpty) throw StateError('meshtastic registry empty');

  print('SETTINGS_REGISTRY_DART_PASS');
}
