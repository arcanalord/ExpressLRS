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

enum DeviceHostProtocol {
  unknown,
  mmUart1,
  ep2LinkAscii,
  crsf,
  ssBridge1,
}

final class RecognitionEvidence {
  const RecognitionEvidence({
    required this.source,
    required this.key,
    required this.value,
  });

  final String source;
  final String key;
  final Object? value;
}

final class DeviceTransportIdentity {
  const DeviceTransportIdentity({
    required this.kind,
    this.vendorId,
    this.productId,
    this.driver,
    this.deviceName,
    this.baudRate,
  });

  final String kind;
  final int? vendorId;
  final int? productId;
  final String? driver;
  final String? deviceName;
  final int? baudRate;
}

final class DeviceRecognitionSnapshot {
  const DeviceRecognitionSnapshot({
    required this.state,
    required this.confidence,
    required this.transport,
    required this.protocol,
    this.protocolVersion,
    this.profileId,
    this.controllerFamily,
    this.radioFamily,
    this.firmwareVersion,
    this.nodeId,
    this.capabilities = const <String>{},
    this.evidence = const <RecognitionEvidence>[],
  });

  final DeviceRecognitionState state;
  final DeviceRecognitionConfidence confidence;
  final DeviceTransportIdentity transport;
  final DeviceHostProtocol protocol;
  final String? protocolVersion;
  final String? profileId;
  final String? controllerFamily;
  final String? radioFamily;
  final String? firmwareVersion;
  final Object? nodeId;
  final Set<String> capabilities;
  final List<RecognitionEvidence> evidence;

  bool get recognized =>
      state == DeviceRecognitionState.recognized &&
      confidence == DeviceRecognitionConfidence.confirmed;

  DeviceRecognitionSnapshot copyWith({
    DeviceRecognitionState? state,
    DeviceRecognitionConfidence? confidence,
    DeviceTransportIdentity? transport,
    DeviceHostProtocol? protocol,
    String? protocolVersion,
    String? profileId,
    String? controllerFamily,
    String? radioFamily,
    String? firmwareVersion,
    Object? nodeId,
    Set<String>? capabilities,
    List<RecognitionEvidence>? evidence,
  }) =>
      DeviceRecognitionSnapshot(
        state: state ?? this.state,
        confidence: confidence ?? this.confidence,
        transport: transport ?? this.transport,
        protocol: protocol ?? this.protocol,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        profileId: profileId ?? this.profileId,
        controllerFamily: controllerFamily ?? this.controllerFamily,
        radioFamily: radioFamily ?? this.radioFamily,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        nodeId: nodeId ?? this.nodeId,
        capabilities: capabilities ?? this.capabilities,
        evidence: evidence ?? this.evidence,
      );
}

abstract final class DeviceRecognition {
  static DeviceRecognitionSnapshot detached() => const DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.detached,
        confidence: DeviceRecognitionConfidence.unknown,
        transport: DeviceTransportIdentity(kind: 'unknown'),
        protocol: DeviceHostProtocol.unknown,
      );

  static DeviceRecognitionSnapshot attachedUsbUart({
    int? vendorId,
    int? productId,
    String? driver,
    String? deviceName,
  }) {
    final evidence = <RecognitionEvidence>[
      if (vendorId != null || productId != null)
        RecognitionEvidence(
          source: 'usb_vid_pid',
          key: 'vid_pid',
          value:
              '${vendorId?.toRadixString(16) ?? '-'}:${productId?.toRadixString(16) ?? '-'}',
        ),
      if (driver != null)
        RecognitionEvidence(
          source: 'serial_driver',
          key: 'driver',
          value: driver,
        ),
    ];
    return DeviceRecognitionSnapshot(
      state: DeviceRecognitionState.attached,
      confidence: DeviceRecognitionConfidence.tentative,
      transport: DeviceTransportIdentity(
        kind: 'usb_uart',
        vendorId: vendorId,
        productId: productId,
        driver: driver,
        deviceName: deviceName,
      ),
      protocol: DeviceHostProtocol.unknown,
      evidence: evidence,
    );
  }

  static DeviceRecognitionSnapshot ep2Link({
    required int baudRate,
    required int nodeId,
    required String firmware,
    required String profileId,
    String? radioFamily,
    Set<String> capabilities = const <String>{
      'text',
      'rssi',
      'snr',
      'wifi_ota',
    },
  }) =>
      DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.recognized,
        confidence: DeviceRecognitionConfidence.confirmed,
        transport: DeviceTransportIdentity(
          kind: 'usb_uart',
          baudRate: baudRate,
        ),
        protocol: DeviceHostProtocol.ep2LinkAscii,
        profileId: profileId,
        radioFamily: radioFamily,
        firmwareVersion: firmware,
        nodeId: nodeId,
        capabilities: capabilities,
        evidence: <RecognitionEvidence>[
          const RecognitionEvidence(
            source: 'protocol_frame',
            key: 'protocol',
            value: 'ep2_link_ascii',
          ),
          RecognitionEvidence(
            source: 'info',
            key: 'node_id',
            value: nodeId,
          ),
          RecognitionEvidence(
            source: 'info',
            key: 'firmware',
            value: firmware,
          ),
          RecognitionEvidence(
            source: 'info',
            key: 'profile_id',
            value: profileId,
          ),
        ],
      );

  static DeviceRecognitionSnapshot crsf({
    required int baudRate,
  }) =>
      DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.recognized,
        confidence: DeviceRecognitionConfidence.confirmed,
        transport: DeviceTransportIdentity(
          kind: 'usb_uart',
          baudRate: baudRate,
        ),
        protocol: DeviceHostProtocol.crsf,
        capabilities: const <String>{'crsf_diagnostics'},
        evidence: const <RecognitionEvidence>[
          RecognitionEvidence(
            source: 'protocol_frame',
            key: 'crc_valid_crsf',
            value: true,
          ),
        ],
      );

  static DeviceRecognitionSnapshot unknownUsbUart({
    int? baudRate,
    String? reason,
  }) =>
      DeviceRecognitionSnapshot(
        state: DeviceRecognitionState.unknown,
        confidence: DeviceRecognitionConfidence.unknown,
        transport: DeviceTransportIdentity(
          kind: 'usb_uart',
          baudRate: baudRate,
        ),
        protocol: DeviceHostProtocol.unknown,
        evidence: <RecognitionEvidence>[
          if (reason != null)
            RecognitionEvidence(
              source: 'protocol_frame',
              key: 'reason',
              value: reason,
            ),
        ],
      );
}
