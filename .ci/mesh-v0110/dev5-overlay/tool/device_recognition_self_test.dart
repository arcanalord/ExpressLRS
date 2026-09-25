import '../lib/core/device_recognition.dart';

void expect(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void main() {
  const provisional = DeviceRecognitionSnapshot(
    state: DeviceRecognitionState.probing,
    confidence: DeviceRecognitionConfidence.tentative,
    transportKind: DeviceTransportKind.usbUart,
    protocol: DeviceHostProtocol.unknown,
    baudRate: 115200,
    evidence: [
      DeviceRecognitionEvidence(
        source: 'usb_vid_pid',
        key: 'vid',
        value: 0x1a86,
      ),
    ],
  );
  expect(!provisional.isConfirmed, 'USB VID/PID must not confirm device identity');

  const confirmed = DeviceRecognitionSnapshot(
    state: DeviceRecognitionState.recognized,
    confidence: DeviceRecognitionConfidence.confirmed,
    transportKind: DeviceTransportKind.usbUart,
    protocol: DeviceHostProtocol.ep2LinkAscii,
    baudRate: 115200,
    profileId: 'EP2-LORA-LAB-01',
    firmwareVersion: 'EP2-LINK-0.2.0',
    nodeId: 1,
    evidence: [
      DeviceRecognitionEvidence(
        source: 'info',
        key: 'firmware',
        value: 'EP2-LINK-0.2.0',
      ),
    ],
  );
  expect(confirmed.isConfirmed, 'INFO-confirmed device must be confirmed');
  expect(
    confirmed.protocol == DeviceHostProtocol.ep2LinkAscii,
    'protocol mapping',
  );

  print('DEVICE_RECOGNITION_SELF_TEST_PASS');
}
