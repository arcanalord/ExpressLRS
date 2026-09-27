final class UsbProfileBinding {
  const UsbProfileBinding({
    required this.profileId,
    required this.vendorId,
    required this.productId,
    required this.driver,
    required this.deviceName,
  });

  final String profileId;
  final int vendorId;
  final int productId;
  final String driver;
  final String deviceName;

  bool matches({
    required int vendorId,
    required int productId,
    required String driver,
    required String deviceName,
  }) {
    if (this.vendorId != vendorId || this.productId != productId) return false;
    final expectedDriver = this.driver.trim().toLowerCase();
    final actualDriver = driver.trim().toLowerCase();
    final expectedName = this.deviceName.trim().toLowerCase();
    final actualName = deviceName.trim().toLowerCase();
    final driverMatches = expectedDriver.isEmpty || expectedDriver == actualDriver;
    final nameMatches = expectedName.isNotEmpty && expectedName == actualName;
    return driverMatches && nameMatches;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'profileId': profileId,
        'vendorId': vendorId,
        'productId': productId,
        'driver': driver,
        'deviceName': deviceName,
      };

  static UsbProfileBinding? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final version = map['version'];
    final profileId = map['profileId']?.toString().trim() ?? '';
    final vendorId = map['vendorId'];
    final productId = map['productId'];
    final driver = map['driver']?.toString() ?? '';
    final deviceName = map['deviceName']?.toString().trim() ?? '';
    if (version != 1 ||
        profileId.isEmpty ||
        vendorId is! num ||
        productId is! num ||
        deviceName.isEmpty) {
      return null;
    }
    final vid = vendorId.toInt();
    final pid = productId.toInt();
    if (vid < 0 || vid > 0xffff || pid < 0 || pid > 0xffff) return null;
    return UsbProfileBinding(
      profileId: profileId,
      vendorId: vid,
      productId: pid,
      driver: driver,
      deviceName: deviceName,
    );
  }
}
