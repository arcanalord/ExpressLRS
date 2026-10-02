import '../services/native_usb_service.dart';
import 'device_recognition.dart';

abstract final class EspServiceDeviceRecognition {
  static DeviceRecognitionSnapshot attached(UsbDeviceInfo device) =>
      DeviceRecognition.attachedUsbUart(
        vendorId: device.vendorId,
        productId: device.productId,
        deviceName: device.deviceName,
      );

  static DeviceRecognitionSnapshot fromProbe(
    UsbDeviceInfo device,
    EspRomProbeResult result,
  ) {
    if (result.meshReady) {
      return _meshConfirmed(device, result);
    }

    if (result.status == 'mesh_caps_unavailable') {
      return DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.probing,
        confidence: DeviceRecognitionConfidence.tentative,
        transport: _transport(device, result),
        protocol: DeviceHostProtocol.mmUart1,
        protocolVersion: result.meshProtocolVersion?.toString(),
        controllerFamily: _clean(result.meshBoardId),
        radioFamily: _clean(result.meshRadioFamily),
        firmwareVersion: _clean(result.meshFirmwareVersion),
        capabilities: const <String>{},
        evidence: <RecognitionEvidence>[
          ..._usbEvidence(device, result),
          const RecognitionEvidence(
            source: 'protocol_frame',
            key: 'protocol',
            value: 'MM-UART/1',
          ),
          const RecognitionEvidence(
            source: 'get_caps',
            key: 'status',
            value: 'unavailable',
          ),
        ],
      );
    }

    if (result.status == 'rom_ready') {
      return DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.recognized,
        confidence: DeviceRecognitionConfidence.serviceConfirmed,
        transport: _transport(device, result),
        protocol: DeviceHostProtocol.unknown,
        controllerFamily:
            _clean(result.chipDescription) ?? _clean(result.chipFamily),
        capabilities: const <String>{},
        evidence: <RecognitionEvidence>[
          ..._usbEvidence(device, result),
          RecognitionEvidence(
            source: 'rom_sync',
            key: 'chip',
            value: _clean(result.chipDescription) ?? _clean(result.chipFamily),
          ),
          if (_clean(result.chipId) != null)
            RecognitionEvidence(
              source: 'rom_sync',
              key: 'chip_id',
              value: result.chipId,
            ),
        ],
      );
    }

    if (result.status == 'no_permission') {
      return DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.attached,
        confidence: DeviceRecognitionConfidence.tentative,
        transport: _transport(device, result),
        protocol: DeviceHostProtocol.unknown,
        evidence: <RecognitionEvidence>[
          ..._usbEvidence(device, result),
          const RecognitionEvidence(
            source: 'usb_permission',
            key: 'granted',
            value: false,
          ),
        ],
      );
    }

    return DeviceRecognitionSnapshot(
      state: result.status == 'serial_error' ||
              result.status == 'open_failed' ||
              result.status == 'no_driver'
          ? DeviceRecognitionState.error
          : DeviceRecognitionState.unknown,
      confidence: DeviceRecognitionConfidence.unknown,
      transport: _transport(device, result),
      protocol: DeviceHostProtocol.unknown,
      capabilities: const <String>{},
      evidence: <RecognitionEvidence>[
        ..._usbEvidence(device, result),
        RecognitionEvidence(
          source: 'protocol_frame',
          key: 'reason',
          value: result.status,
        ),
      ],
    );
  }

  static DeviceRecognitionSnapshot _meshConfirmed(
    UsbDeviceInfo device,
    EspRomProbeResult result,
  ) {
    final capabilities = normalizeCapabilities(result.meshCapabilities);
    final evidence = <RecognitionEvidence>[
      ..._usbEvidence(device, result),
      const RecognitionEvidence(
        source: 'protocol_frame',
        key: 'protocol',
        value: 'MM-UART/1',
      ),
      if (_clean(result.meshBoardId) != null)
        RecognitionEvidence(
          source: 'get_info',
          key: 'board_id',
          value: result.meshBoardId,
        ),
      if (_clean(result.meshFirmwareVersion) != null)
        RecognitionEvidence(
          source: 'get_info',
          key: 'firmware_version',
          value: result.meshFirmwareVersion,
        ),
      if (_clean(result.meshRadioFamily) != null)
        RecognitionEvidence(
          source: 'get_info',
          key: 'radio_family',
          value: result.meshRadioFamily,
        ),
      RecognitionEvidence(
        source: 'get_caps',
        key: 'capabilities',
        value: capabilities.toList()..sort(),
      ),
    ];

    return DeviceRecognitionSnapshot(
      state: DeviceRecognitionState.recognized,
      confidence: DeviceRecognitionConfidence.confirmed,
      transport: _transport(device, result),
      protocol: DeviceHostProtocol.mmUart1,
      protocolVersion: result.meshProtocolVersion?.toString(),
      controllerFamily: _clean(result.meshBoardId),
      radioFamily: _clean(result.meshRadioFamily),
      firmwareVersion: _clean(result.meshFirmwareVersion),
      capabilities: capabilities,
      evidence: evidence,
    );
  }

  static DeviceTransportIdentity _transport(
    UsbDeviceInfo device,
    EspRomProbeResult result,
  ) =>
      DeviceTransportIdentity(
        kind: 'usb_uart',
        vendorId: device.vendorId,
        productId: device.productId,
        driver: _clean(result.driver),
        deviceName: device.deviceName,
        baudRate: result.baudRate,
      );

  static List<RecognitionEvidence> _usbEvidence(
    UsbDeviceInfo device,
    EspRomProbeResult result,
  ) =>
      <RecognitionEvidence>[
        RecognitionEvidence(
          source: 'usb_vid_pid',
          key: 'vid_pid',
          value:
              '${device.vendorId.toRadixString(16)}:${device.productId.toRadixString(16)}',
        ),
        if (_clean(result.driver) != null)
          RecognitionEvidence(
            source: 'serial_driver',
            key: 'driver',
            value: result.driver,
          ),
      ];

  static Set<String> normalizeCapabilities(Map<String, Object?>? raw) {
    if (raw == null) return const <String>{};
    final out = <String>{};

    for (final protocol in _strings(raw['networkProtocols'])) {
      out.add(protocol);
    }

    const flags = <String, String>{
      'positionAvailable': 'position',
      'waypointAvailable': 'waypoint',
      'fileTransferAvailable': 'file',
      'voiceAvailable': 'voice',
      'rangingAvailable': 'ranging',
      'timeSyncAvailable': 'timeSync',
      'rssiAvailable': 'rssi',
      'snrAvailable': 'snr',
      'otaAvailable': 'ota',
    };
    for (final entry in flags.entries) {
      if (raw[entry.key] == true) out.add(entry.value);
    }

    return Set<String>.unmodifiable(out);
  }

  static List<String> _strings(Object? value) {
    if (value is! Iterable) return const <String>[];
    final out = <String>[];
    for (final item in value) {
      final clean = _clean(item?.toString());
      if (clean != null && !out.contains(clean)) out.add(clean);
    }
    return out;
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
