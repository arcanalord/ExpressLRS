import 'package:flutter/services.dart';

class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.vendorId,
    required this.productId,
    required this.deviceName,
    required this.interfaceCount,
    this.manufacturer,
    this.product,
  });

  final int vendorId;
  final int productId;
  final String deviceName;
  final int interfaceCount;
  final String? manufacturer;
  final String? product;

  String get vidPid =>
      '0x${vendorId.toRadixString(16).padLeft(4, '0')}:0x${productId.toRadixString(16).padLeft(4, '0')}';

  String get familyLabel {
    if (vendorId == 0x1a86) return 'WCH USB-UART';
    if (vendorId == 0x10c4) return 'Silicon Labs CP210x';
    if (vendorId == 0x0403) return 'FTDI USB-UART';
    if (vendorId == 0x303a) return 'Espressif USB';
    return 'USB-устройство';
  }

  factory UsbDeviceInfo.fromMap(Map<Object?, Object?> map) {
    return UsbDeviceInfo(
      vendorId: map['vendorId'] as int,
      productId: map['productId'] as int,
      deviceName: map['deviceName'] as String? ?? '-',
      interfaceCount: map['interfaceCount'] as int? ?? 0,
      manufacturer: map['manufacturer'] as String?,
      product: map['product'] as String?,
    );
  }
}

class NativeUsbService {
  static const MethodChannel _channel = MethodChannel('service_studio/native');

  Future<List<UsbDeviceInfo>> listDevices() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listUsbDevices') ??
        const <dynamic>[];
    return raw
        .map((e) => UsbDeviceInfo.fromMap(e as Map<Object?, Object?>))
        .toList(growable: false);
  }

  Future<String> platformInfo() async {
    return await _channel.invokeMethod<String>('platformInfo') ?? 'Android';
  }
}
