import '../core/device_recognition.dart';
import 'radio_capability_contract.dart';

DeviceRecognitionSnapshot deviceRecognitionFromMmUart({
  required RadioInfo info,
  required RadioCapabilities capabilities,
  Map<String, Object?>? hostLink,
}) {
  final normalizedCapabilities = <String>{
    ...capabilities.networkProtocols,
    if (capabilities.positionAvailable) 'position',
    if (capabilities.waypointAvailable) 'waypoint',
    if (capabilities.fileTransferAvailable) 'file',
    if (capabilities.voiceAvailable) 'voice',
    if (capabilities.rangingAvailable) 'ranging',
    if (capabilities.timeSyncAvailable) 'timeSync',
    if (capabilities.rssiAvailable) 'rssi',
    if (capabilities.snrAvailable) 'snr',
  };

  final baudRate = hostLink?['baudRate'] is int
      ? hostLink!['baudRate'] as int
      : null;
  final hostType = _clean(hostLink?['type']);

  return DeviceRecognitionSnapshot(
    state: DeviceRecognitionState.recognized,
    confidence: DeviceRecognitionConfidence.confirmed,
    transport: DeviceTransportIdentity(
      kind: hostType == 'android_usb_serial' ? 'usb_uart' : 'host_link',
      baudRate: baudRate,
    ),
    protocol: DeviceHostProtocol.mmUart1,
    protocolVersion: info.protocolVersion?.toString(),
    controllerFamily: _clean(info.boardId),
    radioFamily: _clean(capabilities.radioFamily) ?? _clean(info.radioFamily),
    firmwareVersion: _clean(info.firmwareVersion),
    capabilities: Set<String>.unmodifiable(normalizedCapabilities),
    evidence: <RecognitionEvidence>[
      const RecognitionEvidence(
        source: 'protocol_frame',
        key: 'protocol',
        value: 'MM-UART/1',
      ),
      if (_clean(info.boardId) != null)
        RecognitionEvidence(
          source: 'get_info',
          key: 'board_id',
          value: info.boardId,
        ),
      if (_clean(info.firmwareVersion) != null)
        RecognitionEvidence(
          source: 'get_info',
          key: 'firmware_version',
          value: info.firmwareVersion,
        ),
      if (_clean(info.radioFamily) != null)
        RecognitionEvidence(
          source: 'get_info',
          key: 'radio_family',
          value: info.radioFamily,
        ),
      RecognitionEvidence(
        source: 'get_caps',
        key: 'capabilities',
        value: normalizedCapabilities.toList()..sort(),
      ),
    ],
  );
}

String? _clean(Object? value) {
  if (value == null) return null;
  final clean = '$value'.trim();
  return clean.isEmpty ? null : clean;
}
