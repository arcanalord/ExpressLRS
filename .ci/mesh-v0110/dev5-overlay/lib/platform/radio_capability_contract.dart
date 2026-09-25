final class RadioInfo {
  const RadioInfo({
    this.protocolVersion,
    this.firmwareFamily,
    this.firmwareVersion,
    this.boardId,
    this.boardRevision,
    this.radioFamily,
    this.buildHash,
    this.bootId,
  });

  final int? protocolVersion;
  final String? firmwareFamily;
  final String? firmwareVersion;
  final String? boardId;
  final String? boardRevision;
  final String? radioFamily;
  final String? buildHash;
  final String? bootId;

  factory RadioInfo.fromJson(Map<String, dynamic> raw, {String? bootId}) =>
      RadioInfo(
        protocolVersion: raw['protocolVersion'] is int
            ? raw['protocolVersion'] as int
            : null,
        firmwareFamily: _cleanString(raw['firmwareFamily']),
        firmwareVersion: _cleanString(raw['firmwareVersion']),
        boardId: _cleanString(raw['boardId']),
        boardRevision: _cleanString(raw['boardRevision']),
        radioFamily: _cleanString(raw['radioFamily']),
        buildHash: _cleanString(raw['buildHash']),
        bootId: _cleanString(raw['bootId']) ?? _cleanString(bootId),
      );
}

final class RadioCapabilities {
  const RadioCapabilities({
    this.schemaVersion = 1,
    this.radioFamily,
    this.profileIds = const [],
    this.networkProtocols = const [],
    this.frequencyRanges = const [],
    this.maxPayload,
    this.txPowerRange,
    this.duplexMode,
    this.positionAvailable = false,
    this.waypointAvailable = false,
    this.fileTransferAvailable = false,
    this.voiceAvailable = false,
    this.rangingAvailable = false,
    this.timeSyncAvailable = false,
    this.rssiAvailable = false,
    this.snrAvailable = false,
  });

  final int schemaVersion;
  final String? radioFamily;
  final List<String> profileIds;
  final List<String> networkProtocols;
  final List<(double, double)> frequencyRanges;
  final int? maxPayload;
  final (double, double)? txPowerRange;
  final String? duplexMode;
  final bool positionAvailable;
  final bool waypointAvailable;
  final bool fileTransferAvailable;
  final bool voiceAvailable;
  final bool rangingAvailable;
  final bool timeSyncAvailable;
  final bool rssiAvailable;
  final bool snrAvailable;

  bool get supportsMmrp => networkProtocols.contains('MMRP/1');

  bool supports(String feature) => switch (feature) {
    'position' => positionAvailable,
    'waypoint' => waypointAvailable,
    'file' => fileTransferAvailable,
    'voice' => voiceAvailable,
    'ranging' => rangingAvailable,
    'timeSync' => timeSyncAvailable,
    'rssi' => rssiAvailable,
    'snr' => snrAvailable,
    _ => false,
  };

  factory RadioCapabilities.fromJson(
    Map<String, dynamic> raw, {
    RadioInfo? info,
  }) {
    final maxPayloadNumber = _finiteNumber(raw['maxPayload']);
    final maxPayload = maxPayloadNumber != null && maxPayloadNumber > 0
        ? maxPayloadNumber.floor()
        : null;
    final protocols = _uniqueStrings(raw['networkProtocols']);
    return RadioCapabilities(
      radioFamily: _cleanString(raw['radioFamily']) ?? info?.radioFamily,
      profileIds: _uniqueStrings(raw['profileIds']),
      networkProtocols: protocols,
      frequencyRanges: _ranges(raw['frequencyRanges']),
      maxPayload: maxPayload,
      txPowerRange: _range(raw['txPowerRange']),
      duplexMode: _cleanString(raw['duplexMode']),
      positionAvailable: raw['positionAvailable'] == true,
      waypointAvailable: raw['waypointAvailable'] == true,
      fileTransferAvailable: raw['fileTransferAvailable'] == true,
      voiceAvailable: raw['voiceAvailable'] == true,
      rangingAvailable: raw['rangingAvailable'] == true,
      timeSyncAvailable: raw['timeSyncAvailable'] == true,
      rssiAvailable: raw['rssiAvailable'] == true,
      snrAvailable: raw['snrAvailable'] == true,
    );
  }
}

String? _cleanString(Object? value) {
  if (value == null) return null;
  final clean = '$value'.trim();
  return clean.isEmpty ? null : clean;
}

double? _finiteNumber(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  final parsed = double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

List<String> _uniqueStrings(Object? value) {
  if (value is! List) return const [];
  final result = <String>[];
  final seen = <String>{};
  for (final item in value) {
    final clean = _cleanString(item);
    if (clean != null && seen.add(clean)) result.add(clean);
  }
  return List.unmodifiable(result);
}

(double, double)? _range(Object? value) {
  if (value is! List || value.length < 2) return null;
  final min = _finiteNumber(value[0]);
  final max = _finiteNumber(value[1]);
  if (min == null || max == null || min > max) return null;
  return (min, max);
}

List<(double, double)> _ranges(Object? value) {
  if (value is! List) return const [];
  final result = <(double, double)>[];
  for (final item in value) {
    final parsed = _range(item);
    if (parsed != null) result.add(parsed);
  }
  return List.unmodifiable(result);
}
