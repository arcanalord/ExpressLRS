import '../lib/core/device_recognition.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final attached = DeviceRecognition.attachedUsbUart(
    vendorId: 0x1a86,
    productId: 0x55d3,
    driver: 'Ch34xSerialDriver',
  );
  check(attached.protocol == DeviceHostProtocol.unknown,
      'VID/PID must not identify EP2');

  final ep2 = DeviceRecognition.ep2Link(
    baudRate: 115200,
    nodeId: 1,
    firmware: 'EP2-LINK-0.2.0',
    profileId: 'EP2-LORA-LAB-01',
    radioFamily: 'sx1280',
  );
  check(ep2.recognized, 'EP2 INFO must confirm device');
  check(ep2.protocol == DeviceHostProtocol.ep2LinkAscii, 'EP2 protocol');
  check(ep2.nodeId == 1, 'node');

  final crsf = DeviceRecognition.crsf(baudRate: 420000);
  check(crsf.recognized, 'valid CRSF frame confirms protocol');
  check(!crsf.capabilities.contains('text'),
      'CRSF diagnostics must not become Messenger text transport');

  final unknown = DeviceRecognition.unknownUsbUart(
    baudRate: 420000,
    reason: 'UART_PROTOCOL_UNKNOWN',
  );
  check(!unknown.recognized, 'unknown must not inherit old identity');
  check(unknown.profileId == null && unknown.firmwareVersion == null,
      'unknown snapshot must not contain stale device metadata');

  print('DEVICE_RECOGNITION_MODEL_V1_PASS');
}
