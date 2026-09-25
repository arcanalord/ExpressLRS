import 'dart:convert';

enum ServiceTarget { device, controller, radio, bareRadio }
enum ServiceAction { identify, update, diagnose, recover }

class DeviceProfile {
  const DeviceProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.controller,
    required this.radio,
    required this.elrs,
    required this.hostProtocols,
    required this.notes,
  });

  final String id;
  final String name;
  final String kind;
  final Map<String, dynamic>? controller;
  final Map<String, dynamic> radio;
  final Map<String, dynamic>? elrs;
  final List<String> hostProtocols;
  final List<String> notes;

  factory DeviceProfile.fromJson(Map<String, dynamic> json) {
    return DeviceProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: json['kind'] as String,
      controller: (json['controller'] as Map?)?.cast<String, dynamic>(),
      radio: (json['radio'] as Map).cast<String, dynamic>(),
      elrs: (json['elrs'] as Map?)?.cast<String, dynamic>(),
      hostProtocols: (json['hostProtocols'] as List<dynamic>? ?? const [])
          .cast<String>(),
      notes: (json['notes'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  String? get elrsTargetPath => elrs?['targetPath']?.toString();
  String? get elrsProductName => elrs?['productName']?.toString();
}

List<DeviceProfile> parseProfiles(String raw) {
  final data = jsonDecode(raw) as List<dynamic>;
  return data
      .map((e) => DeviceProfile.fromJson((e as Map).cast<String, dynamic>()))
      .toList(growable: false);
}
