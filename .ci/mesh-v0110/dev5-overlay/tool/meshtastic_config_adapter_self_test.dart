import '../lib/core/settings_registry.dart';
import '../lib/platform/meshtastic_config_adapter.dart';

void main() {
  const adapter = MeshtasticConfigAdapter();

  final original = MeshtasticConfigSnapshot(
    firmwareVersion: '2.8.0',
    config: {
      'device': {
        'role': 'CLIENT',
        'future_unknown': 77,
      },
      'position': {
        'position_broadcast_secs': 900,
      },
      'power': {
        'is_power_saving': false,
      },
      'network': {
        'wifi_enabled': false,
        'future_network_field': 'keep-me',
      },
      'display': {
        'screen_on_secs': 60,
      },
      'lora': {
        'region': 'EU_868',
        'tx_power': 10,
      },
      'bluetooth': {
        'enabled': true,
      },
      'security': {
        'is_managed': false,
        'packet_signature_policy':
            'PACKET_SIGNATURE_POLICY_COMPATIBLE',
      },
      'device_ui': {
        'screen_brightness': 128,
      },
      'future_config_variant': {
        'opaque': true,
      },
    },
    moduleConfig: {
      'mqtt': {
        'enabled': false,
        'address': 'mqtt.example',
      },
      'telemetry': {
        'device_telemetry_enabled': true,
      },
      'future_module': {
        'x': 1,
      },
    },
  );

  final currentRole = adapter.read(
    original,
    'meshtastic.device.role',
    capabilities: {'tx_power_configurable'},
  );
  if (currentRole != 'CLIENT') throw StateError('read failed');

  final patched = adapter.patch(
    original,
    {
      'meshtastic.device.role': 'CLIENT_BASE',
      'meshtastic.network.wifi_enabled': true,
      'meshtastic.device_ui.screen_brightness': 200,
      'meshtastic.security.packet_signature_policy':
          'PACKET_SIGNATURE_POLICY_BALANCED',
      'meshtastic.mqtt.enabled': true,
      'meshtastic.lora.tx_power': 17,
    },
    capabilities: {'tx_power_configurable'},
  );

  if (patched.config['device']['role'] != 'CLIENT_BASE') {
    throw StateError('device patch failed');
  }
  if (patched.moduleConfig['mqtt']['enabled'] != true) {
    throw StateError('module patch failed');
  }
  if (patched.config['device']['future_unknown'] != 77 ||
      patched.config['network']['future_network_field'] != 'keep-me' ||
      patched.config['future_config_variant']['opaque'] != true ||
      patched.moduleConfig['future_module']['x'] != 1) {
    throw StateError('unknown fields were not preserved');
  }
  if (original.config['device']['role'] != 'CLIENT' ||
      original.moduleConfig['mqtt']['enabled'] != false) {
    throw StateError('adapter mutated original snapshot');
  }

  var rejected = false;
  try {
    adapter.patch(
      original,
      {'meshtastic.device_ui.screen_brightness': 300},
      capabilities: {'tx_power_configurable'},
    );
  } on ArgumentError {
    rejected = true;
  }
  if (!rejected) throw StateError('range validation failed');

  rejected = false;
  try {
    adapter.patch(
      original,
      {'meshtastic.lora.tx_power': 20},
    );
  } on StateError {
    rejected = true;
  }
  if (!rejected) throw StateError('capability enforcement failed');

  final oldFirmware = MeshtasticConfigSnapshot(
    firmwareVersion: '2.7.19',
    config: original.config,
    moduleConfig: original.moduleConfig,
  );
  rejected = false;
  try {
    adapter.patch(
      oldFirmware,
      {
        'meshtastic.security.packet_signature_policy':
            'PACKET_SIGNATURE_POLICY_STRICT',
      },
    );
  } on StateError {
    rejected = true;
  }
  if (!rejected) throw StateError('firmware gate failed');

  final available = adapter.readAvailable(
    patched,
    capabilities: {'tx_power_configurable'},
  );
  if (available['meshtastic.mqtt.enabled'] != true ||
      available['meshtastic.device.role'] != 'CLIENT_BASE') {
    throw StateError('readAvailable failed');
  }

  print('MESHTASTIC_CONFIG_ADAPTER_PASS');
}
