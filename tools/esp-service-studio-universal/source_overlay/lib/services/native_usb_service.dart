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


class ElrsCatalogResult {
  const ElrsCatalogResult({
    required this.status,
    this.message,
    this.version,
    this.releaseName,
    this.publishedAt,
    this.commitSha,
    this.targetPath,
    this.productName,
    this.platform,
    this.firmware,
    this.layoutFile,
    this.minVersion,
    this.uploadMethods = const [],
  });

  final String status;
  final String? message;
  final String? version;
  final String? releaseName;
  final String? publishedAt;
  final String? commitSha;
  final String? targetPath;
  final String? productName;
  final String? platform;
  final String? firmware;
  final String? layoutFile;
  final String? minVersion;
  final List<String> uploadMethods;

  bool get ok => status == 'ok';

  factory ElrsCatalogResult.fromMap(Map<Object?, Object?> map) {
    return ElrsCatalogResult(
      status: map['status'] as String? ?? 'error',
      message: map['message'] as String?,
      version: map['version'] as String?,
      releaseName: map['releaseName'] as String?,
      publishedAt: map['publishedAt'] as String?,
      commitSha: map['commitSha'] as String?,
      targetPath: map['targetPath'] as String?,
      productName: map['productName'] as String?,
      platform: map['platform'] as String?,
      firmware: map['firmware'] as String?,
      layoutFile: map['layoutFile'] as String?,
      minVersion: map['minVersion'] as String?,
      uploadMethods: (map['uploadMethods'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class ElrsPreparedFirmware {
  const ElrsPreparedFirmware({
    required this.status,
    this.message,
    this.version,
    this.productName,
    this.platform,
    this.firmware,
    this.regulatoryProfile,
    this.writeOffset,
    this.filePath,
    this.fileSize,
    this.sha256,
    this.readyToFlash = false,
  });

  final String status;
  final String? message;
  final String? version;
  final String? productName;
  final String? platform;
  final String? firmware;
  final String? regulatoryProfile;
  final String? writeOffset;
  final String? filePath;
  final int? fileSize;
  final String? sha256;
  final bool readyToFlash;

  bool get ok => status == 'prepared' && readyToFlash;

  factory ElrsPreparedFirmware.fromMap(Map<Object?, Object?> map) {
    return ElrsPreparedFirmware(
      status: map['status'] as String? ?? 'error',
      message: map['message'] as String?,
      version: map['version'] as String?,
      productName: map['productName'] as String?,
      platform: map['platform'] as String?,
      firmware: map['firmware'] as String?,
      regulatoryProfile: map['regulatoryProfile'] as String?,
      writeOffset: map['writeOffset'] as String?,
      filePath: map['filePath'] as String?,
      fileSize: map['fileSize'] as int?,
      sha256: map['sha256'] as String?,
      readyToFlash: map['readyToFlash'] as bool? ?? false,
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

  Future<ElrsCatalogResult> fetchOfficialElrsTarget({
    required String targetPath,
    required String expectedProductName,
    required String expectedPlatform,
    required String expectedFirmware,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'fetchOfficialElrsTarget',
          <String, Object?>{
            'targetPath': targetPath,
            'expectedProductName': expectedProductName,
            'expectedPlatform': expectedPlatform,
            'expectedFirmware': expectedFirmware,
          },
        ) ??
        const <dynamic, dynamic>{};
    return ElrsCatalogResult.fromMap(raw.cast<Object?, Object?>());
  }

  Future<ElrsPreparedFirmware> prepareOfficialElrsTarget({
    required String targetPath,
    required String expectedProductName,
    required String expectedPlatform,
    required String expectedFirmware,
    required String regulatoryProfile,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'prepareOfficialElrsTarget',
          <String, Object?>{
            'targetPath': targetPath,
            'expectedProductName': expectedProductName,
            'expectedPlatform': expectedPlatform,
            'expectedFirmware': expectedFirmware,
            'regulatoryProfile': regulatoryProfile,
          },
        ) ??
        const <dynamic, dynamic>{};
    return ElrsPreparedFirmware.fromMap(raw.cast<Object?, Object?>());
  }

  Future<String> platformInfo() async {
    return await _channel.invokeMethod<String>('platformInfo') ?? 'Android';
  }
}
