import 'dart:convert';
import 'dart:io';

import '../core/usb_profile_binding.dart';

final class UsbProfileBindingStore {
  UsbProfileBindingStore(Directory root)
      : _file = File('${root.path}/usb_profile_binding_v1.json');

  final File _file;

  Future<UsbProfileBinding?> load() async {
    try {
      if (!await _file.exists()) return null;
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return null;
      return UsbProfileBinding.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UsbProfileBinding binding) async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(binding.toJson()), flush: true);
    if (await _file.exists()) {
      await _file.delete();
    }
    await temporary.rename(_file.path);
  }

  Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}
