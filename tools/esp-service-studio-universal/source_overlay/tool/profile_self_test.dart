import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/device_profiles.json');
  if (!file.existsSync()) {
    stderr.writeln('device_profiles.json missing');
    exit(2);
  }
  final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  if (raw.length < 5) {
    stderr.writeln('expected at least 5 device profiles');
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
  }
  final ep2 = raw.cast<Map<String, dynamic>>().firstWhere(
        (e) => e['id'] == 'ep2_esp8285_sx1280',
      );
  final controller = ep2['controller'] as Map<String, dynamic>;
  final offsets = (controller['defaultOffsets'] as List<dynamic>).cast<String>();
  if (controller['family'] != 'esp8285' || offsets.single != '0x0') {
    stderr.writeln('EP2 defaults are not safe');
    exit(6);
  }
  stdout.writeln('Service Studio profile self-test PASS (${raw.length} profiles)');
}
