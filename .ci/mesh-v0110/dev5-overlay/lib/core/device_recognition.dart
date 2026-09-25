enum DeviceRecognitionState {
  detached,
  attached,
  probing,
  recognized,
  unknown,
  error,
}

enum DeviceRecognitionConfidence {
  unknown,
  tentative,
  confirmed,
  serviceConfirmed,
}

enum DeviceTransportKind {
  usbUart,
  nativeUsb,
  ble,
  wifi,
  unknown,
}

enum DeviceHostProtocol {
  unknown,
  mmUart1,
  ep2LinkAscii,
  crsf,
  ssBridge1,
}

final class DeviceRecognitionEvidence {
  const DeviceRecognitionEvidence({
    required this.source,
    required this.key,
    required this.value,
  });

  final String source;
  final String key;
  final Object? value;
}

final class DeviceRecognitionSnapshot {
  const DeviceRecognitionSnapshot({
    required this.state,
    required this.confidence,
    required this.transportKind,
    required this.protocol,
    this.vendorId,
    this.productId,
    this.driver,
    this.deviceName,
    this.baudRate,
    this.profileId,
    this.controllerFamily,
    this.radioFamily,
    this.firmwareVersion,
    this.nodeId,
    this.capabilities = const <String>[],
    this.evidence = const <DeviceRecognitionEvidence>[],
  });

  final DeviceRecognitionState state;
  final DeviceRecognitionConfidence confidence;
  final DeviceTransportKind transportKind;
  final DeviceHostProtocol protocol;

  final int? vendorId;
  final int? productId;
  final String? driver;
  final String? deviceName;
  final int? baudRate;

  final String? profileId;
  final String? controllerFamily;
  final String? radioFamily;
  final String? firmwareVersion;
  final Object? nodeId;

  final List<String> capabilities;
  final List<DeviceRecognitionEvidence> evidence;

  bool get isConfirmed =>
      confidence == DeviceRecognitionConfidence.confirmed ||
      confidence == DeviceRecognitionConfidence.serviceConfirmed;
}
