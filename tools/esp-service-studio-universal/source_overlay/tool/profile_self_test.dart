import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/device_profiles.json');
  if (!file.existsSync()) {
    stderr.writeln('device_profiles.json missing');
    exit(2);
  }

  final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  if (raw.length < 4) {
    stderr.writeln('expected at least 4 custom device profiles');
    exit(3);
  }

  final ids = <String>{};
  for (final item in raw.cast<Map<String, dynamic>>()) {
    final id = item['id'] as String?;
    final radio = item['radio'] as Map<String, dynamic>?;
    if (id == null || id.isEmpty || !ids.add(id)) {
      stderr.writeln('invalid/duplicate profile id: $id');
      exit(4);
    }
    if (radio == null || radio['family'] == null || radio['serviceKind'] == null) {
      stderr.writeln('profile $id lacks radio service model');
      exit(5);
    }
    if (item.containsKey('elrs')) {
      stderr.writeln('official ELRS targets must not be hardcoded in local profiles: $id');
      exit(6);
    }
  }

  const required = {
    'mesh_esp32s3_lr2021',
    'mesh_esp32s3_lr1121',
    'universal_esp32s3_sx1280',
    'bare_radio_service_bridge',
  };

  if (!ids.containsAll(required)) {
    stderr.writeln('missing required custom service profiles');
    exit(7);
  }

  stdout.writeln(
    'Service Studio profile self-test PASS (' + raw.length.toString() + ' custom profiles; ELRS dynamic)',
  );
}
