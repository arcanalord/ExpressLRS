import 'package:flutter/services.dart';

class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.vendorId,
    required this.productId,
    required this.deviceName,
    required this.interfaceCount,
    required this.hasPermission,
    this.manufacturer,
    this.product,
  });

  final int vendorId;
  final int productId;
  final String deviceName;
  final int interfaceCount;
  final bool hasPermission;
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
      hasPermission: map['hasPermission'] as bool? ?? false,
      manufacturer: map['manufacturer'] as String?,
      product: map['product'] as String?,
    );
  }
}

class UsbSnapshot {
  const UsbSnapshot({
    required this.event,
    required this.devices,
  });

  final String event;
  final List<UsbDeviceInfo> devices;

  factory UsbSnapshot.fromMap(Map<Object?, Object?> map) {
    final raw = map['devices'] as List<dynamic>? ?? const <dynamic>[];
    return UsbSnapshot(
      event: map['event'] as String? ?? 'snapshot',
      devices: raw
          .map((e) => UsbDeviceInfo.fromMap(e as Map<Object?, Object?>))
          .toList(growable: false),
    );
  }
}

class EspRomProbeResult {
  const EspRomProbeResult({
    required this.status,
    required this.message,
    this.driver,
    this.baudRate,
    this.bytesRead,
    this.elapsedMs,
    this.chipFamily,
    this.chipDescription,
    this.chipMagic,
    this.chipId,
    this.mac,
    this.flashId,
    this.flashVendorId,
    this.flashDeviceId,
    this.flashSize,
    this.flashEmbedded,
  });

  final String status;
  final String message;
  final String? driver;
  final int? baudRate;
  final int? bytesRead;
  final int? elapsedMs;
  final String? chipFamily;
  final String? chipDescription;
  final String? chipMagic;
  final String? chipId;
  final String? mac;
  final String? flashId;
  final int? flashVendorId;
  final String? flashDeviceId;
  final String? flashSize;
  final bool? flashEmbedded;

  bool get ok => status == 'rom_ready';

  factory EspRomProbeResult.fromMap(Map<Object?, Object?> map) {
    return EspRomProbeResult(
      status: map['status'] as String? ?? 'unknown',
      message: map['message'] as String? ?? 'Нет сообщения',
      driver: map['driver'] as String?,
      baudRate: map['baudRate'] as int?,
      bytesRead: map['bytesRead'] as int?,
      elapsedMs: map['elapsedMs'] as int?,
      chipFamily: map['chipFamily'] as String?,
      chipDescription: map['chipDescription'] as String?,
      chipMagic: map['chipMagic'] as String?,
      chipId: map['chipId'] as String?,
      mac: map['mac'] as String?,
      flashId: map['flashId'] as String?,
      flashVendorId: map['flashVendorId'] as int?,
      flashDeviceId: map['flashDeviceId'] as String?,
      flashSize: map['flashSize'] as String?,
      flashEmbedded: map['flashEmbedded'] as bool?,
    );
  }
}

class NativeUsbService {
  static const MethodChannel _channel = MethodChannel('service_studio/native');
  static const EventChannel _events = EventChannel('service_studio/usb_events');

  Future<List<UsbDeviceInfo>> listDevices() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listUsbDevices') ??
        const <dynamic>[];

    return raw
        .map((e) => UsbDeviceInfo.fromMap(e as Map<Object?, Object?>))
        .toList(growable: false);
  }

  Stream<UsbSnapshot> watchDevices() {
    return _events.receiveBroadcastStream().map(
          (event) => UsbSnapshot.fromMap(
            event as Map<Object?, Object?>,
          ),
        );
  }

  Future<EspRomProbeResult> probeEspRom({
    required String deviceName,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'probeEspRom',
          <String, Object?>{
            'deviceName': deviceName,
          },
        ) ??
        const <dynamic, dynamic>{};

    return EspRomProbeResult.fromMap(
      raw.cast<Object?, Object?>(),
    );
  }

  Future<String> platformInfo() async {
    return await _channel.invokeMethod<String>('platformInfo') ?? 'Android';
  }
}
