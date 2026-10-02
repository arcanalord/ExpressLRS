import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:service_studio/models/device_recognition.dart';
import 'package:service_studio/models/esp_service_device_recognition.dart';
import 'package:service_studio/services/native_usb_service.dart';

void main() {
  test('VID/PID alone never identifies an M03/EP2 device', () {
    const device = UsbDeviceInfo(
      vendorId: 0x1a86,
      productId: 0x55d3,
      deviceName: '/dev/test',
      interfaceCount: 1,
      hasPermission: true,
    );
    final snapshot = EspServiceDeviceRecognition.attached(device);
    expect(snapshot.state, DeviceRecognitionState.attached);
    expect(snapshot.confidence, DeviceRecognitionConfidence.tentative);
    expect(snapshot.protocol, DeviceHostProtocol.unknown);
    expect(snapshot.profileId, isNull);
    expect(snapshot.firmwareVersion, isNull);
    expect(snapshot.capabilities, isEmpty);
  });

  test('MM-UART GET_INFO + GET_CAPS maps to canonical snapshot v1', () {
    final raw = jsonDecode(
      File('test/fixtures/device_recognition_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final usb = raw['usb'] as Map<String, dynamic>;
    final probe = raw['probe'] as Map<String, dynamic>;
    final expected = raw['expected'] as Map<String, dynamic>;

    final device = UsbDeviceInfo(
      vendorId: usb['vendorId'] as int,
      productId: usb['productId'] as int,
      deviceName: usb['deviceName'] as String,
      interfaceCount: usb['interfaceCount'] as int,
      hasPermission: usb['hasPermission'] as bool,
      manufacturer: usb['manufacturer'] as String?,
      product: usb['product'] as String?,
    );
    final result = EspRomProbeResult(
      status: probe['status'] as String,
      message: probe['message'] as String,
      driver: probe['driver'] as String?,
      baudRate: probe['baudRate'] as int?,
      meshProtocolVersion: probe['meshProtocolVersion'] as int?,
      meshFirmwareFamily: probe['meshFirmwareFamily'] as String?,
      meshFirmwareVersion: probe['meshFirmwareVersion'] as String?,
      meshBoardId: probe['meshBoardId'] as String?,
      meshRadioFamily: probe['meshRadioFamily'] as String?,
      meshBuildHash: probe['meshBuildHash'] as String?,
      meshCapabilities:
          (probe['meshCapabilities'] as Map).cast<String, Object?>(),
    );

    final snapshot = EspServiceDeviceRecognition.fromProbe(device, result);
    expect(snapshot.state.name, expected['state']);
    expect(snapshot.confidence.name, expected['confidence']);
    expect(snapshot.transport.kind, expected['transportKind']);
    expect(snapshot.protocol.name, expected['protocol']);
    expect(snapshot.protocolVersion, expected['protocolVersion']);
    expect(snapshot.controllerFamily, expected['controllerFamily']);
    expect(snapshot.radioFamily, expected['radioFamily']);
    expect(snapshot.firmwareVersion, expected['firmwareVersion']);

    final actualCaps = snapshot.capabilities.toList()..sort();
    expect(actualCaps, (expected['capabilities'] as List).cast<String>());

    expect(
      snapshot.evidence.any(
        (e) => e.source == 'get_caps' && e.key == 'capabilities',
      ),
      isTrue,
    );
    expect(
      snapshot.evidence.any(
        (e) => e.source == 'get_info' && e.key == 'board_id',
      ),
      isTrue,
    );
  });

  test('missing GET_CAPS never invents capabilities', () {
    const device = UsbDeviceInfo(
      vendorId: 0x1a86,
      productId: 0x55d3,
      deviceName: '/dev/test',
      interfaceCount: 1,
      hasPermission: true,
    );
    const result = EspRomProbeResult(
      status: 'mesh_caps_unavailable',
      message: 'GET_INFO passed, GET_CAPS unavailable',
      driver: 'Ch34xSerialDriver',
      baudRate: 115200,
      meshProtocolVersion: 1,
      meshFirmwareVersion: '0.4.1-dev',
      meshBoardId: 'ep2',
      meshRadioFamily: 'SX1280',
    );

    final snapshot = EspServiceDeviceRecognition.fromProbe(device, result);
    expect(snapshot.protocol, DeviceHostProtocol.mmUart1);
    expect(snapshot.state, DeviceRecognitionState.probing);
    expect(snapshot.confidence, DeviceRecognitionConfidence.tentative);
    expect(snapshot.capabilities, isEmpty);
    expect(
      snapshot.evidence.any(
        (e) =>
            e.source == 'get_caps' &&
            e.key == 'status' &&
            e.value == 'unavailable',
      ),
      isTrue,
    );
  });

  test('service ROM recognition stays separate from host protocol identity', () {
    const device = UsbDeviceInfo(
      vendorId: 0x1a86,
      productId: 0x55d3,
      deviceName: '/dev/test',
      interfaceCount: 1,
      hasPermission: true,
    );
    const result = EspRomProbeResult(
      status: 'rom_ready',
      message: 'ESP ROM ready',
      driver: 'Ch34xSerialDriver',
      baudRate: 115200,
      chipFamily: 'Espressif',
      chipDescription: 'ESP8285',
      chipId: '1234',
    );

    final snapshot = EspServiceDeviceRecognition.fromProbe(device, result);
    expect(
      snapshot.confidence,
      DeviceRecognitionConfidence.serviceConfirmed,
    );
    expect(snapshot.protocol, DeviceHostProtocol.unknown);
    expect(snapshot.controllerFamily, 'ESP8285');
    expect(snapshot.capabilities, isEmpty);
  });

  test('unknown probe does not retain stale identity', () {
    const device = UsbDeviceInfo(
      vendorId: 0x1a86,
      productId: 0x55d3,
      deviceName: '/dev/test',
      interfaceCount: 1,
      hasPermission: true,
    );
    const result = EspRomProbeResult(
      status: 'rom_sync_timeout',
      message: 'No protocol',
      driver: 'Ch34xSerialDriver',
      baudRate: 115200,
    );

    final snapshot = EspServiceDeviceRecognition.fromProbe(device, result);
    expect(snapshot.state, DeviceRecognitionState.unknown);
    expect(snapshot.protocol, DeviceHostProtocol.unknown);
    expect(snapshot.profileId, isNull);
    expect(snapshot.firmwareVersion, isNull);
    expect(snapshot.capabilities, isEmpty);
  });
}
