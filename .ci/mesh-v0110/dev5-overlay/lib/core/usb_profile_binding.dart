final class UsbProfileBinding {
  const UsbProfileBinding({
    required this.profileId,
    required this.vendorId,
    required this.productId,
    required this.driver,
  });

  final String profileId;
  final int vendorId;
  final int productId;
  final String driver;

  bool matches({
    required int vendorId,
    required int productId,
    required String driver,
  }) {
    if (this.vendorId != vendorId || this.productId != productId) return false;
    final expectedDriver = this.driver.trim().toLowerCase();
    final actualDriver = driver.trim().toLowerCase();
    return expectedDriver.isEmpty || expectedDriver == actualDriver;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'profileId': profileId,
        'vendorId': vendorId,
        'productId': productId,
        'driver': driver,
      };

  static UsbProfileBinding? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final version = map['version'];
    final profileId = map['profileId']?.toString().trim() ?? '';
    final vendorId = map['vendorId'];
    final productId = map['productId'];
    final driver = map['driver']?.toString() ?? '';
    if (version != 1 ||
        profileId.isEmpty ||
        vendorId is! num ||
        productId is! num) {
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
    );
  }
}
