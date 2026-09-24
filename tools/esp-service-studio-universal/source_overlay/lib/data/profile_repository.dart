import 'package:flutter/services.dart';

import '../models/service_models.dart';

class ProfileRepository {
  Future<List<DeviceProfile>> load() async {
    final raw = await rootBundle.loadString('assets/device_profiles.json');
    return parseProfiles(raw);
  }
}
