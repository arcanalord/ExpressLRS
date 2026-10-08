const int meshDefaultRequestedPowerMw = 100;

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

final class RadioPowerStep {
  const RadioPowerStep({
    required this.id,
    required this.nominalMw,
    required this.radiatedPowerCalibrated,
    required this.normalUiRecommended,
    required this.autoEligible,
    this.independentBenchVerified = false,
    this.calibrationSource,
  });

  final String id;
  final int nominalMw;
  final bool radiatedPowerCalibrated;
  final bool independentBenchVerified;
  final bool normalUiRecommended;
  final bool autoEligible;
  final String? calibrationSource;

  factory RadioPowerStep.fromJson(Map<String, dynamic> raw) {
    final id = _cleanString(raw['id']);
    final nominal = _positiveInt(raw['nominalMw']);
    if (id == null || nominal == null) {
      throw const FormatException('INVALID_POWER_STEP');
    }
    return RadioPowerStep(
      id: id,
      nominalMw: nominal,
      radiatedPowerCalibrated: raw['radiatedPowerCalibrated'] == true,
      independentBenchVerified: raw['independentBenchVerified'] == true,
      normalUiRecommended: raw['normalUiRecommended'] == true,
      autoEligible: raw['autoEligible'] == true,
      calibrationSource: _cleanString(raw['calibrationSource']),
    );
  }
}

final class RadioPowerSelection {
  const RadioPowerSelection({
    required this.requestedMw,
    required this.step,
    required this.exact,
  });

  final int requestedMw;
  final RadioPowerStep step;
  final bool exact;

  int get actualMw => step.nominalMw;
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
    this.powerControlAvailable = false,
    this.powerControlVersion,
    this.powerUnit,
    this.powerDefaultId,
    this.powerCalibrationSource,
    this.autoPowerAvailable = false,
    this.powerSteps = const [],
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
  final bool powerControlAvailable;
  final int? powerControlVersion;
  final String? powerUnit;
  final String? powerDefaultId;
  final String? powerCalibrationSource;
  final bool autoPowerAvailable;
  final List<RadioPowerStep> powerSteps;

  bool get supportsMmrp => networkProtocols.contains('MMRP/1');

  List<RadioPowerStep> get selectablePowerSteps {
    final result =
        powerSteps
            .where(
              (step) =>
                  step.radiatedPowerCalibrated && step.normalUiRecommended,
            )
            .toList(growable: false)
          ..sort((a, b) => a.nominalMw.compareTo(b.nominalMw));
    return List.unmodifiable(result);
  }

  RadioPowerSelection? selectPowerStep(
    int requestedMw, {
    int defaultMw = meshDefaultRequestedPowerMw,
  }) {
    final steps = selectablePowerSteps;
    if (!powerControlAvailable || steps.isEmpty) return null;
    final requested = requestedMw > 0 ? requestedMw : defaultMw;
    for (final step in steps) {
      if (step.nominalMw == requested) {
        return RadioPowerSelection(
          requestedMw: requested,
          step: step,
          exact: true,
        );
      }
    }
    RadioPowerStep? lower;
    for (final step in steps) {
      if (step.nominalMw < requested) lower = step;
    }
    final selected = lower ?? steps.first;
    return RadioPowerSelection(
      requestedMw: requested,
      step: selected,
      exact: false,
    );
  }

  bool supports(String feature) => switch (feature) {
    'position' => positionAvailable,
    'waypoint' => waypointAvailable,
    'file' => fileTransferAvailable,
    'voice' => voiceAvailable,
    'ranging' => rangingAvailable,
    'timeSync' => timeSyncAvailable,
    'rssi' => rssiAvailable,
    'snr' => snrAvailable,
    'power' => powerControlAvailable && selectablePowerSteps.isNotEmpty,
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
    final powerSteps = _powerSteps(raw['powerSteps']);
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
      powerControlAvailable:
          raw['powerControlAvailable'] == true && powerSteps.isNotEmpty,
      powerControlVersion: _positiveInt(raw['powerControlVersion']),
      powerUnit: _cleanString(raw['powerUnit']),
      powerDefaultId: _cleanString(raw['powerDefaultId']),
      powerCalibrationSource: _cleanString(raw['powerCalibrationSource']),
      autoPowerAvailable: raw['autoPowerAvailable'] == true,
      powerSteps: powerSteps,
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

int? _positiveInt(Object? value) {
  final parsed = _finiteNumber(value);
  if (parsed == null || parsed <= 0) return null;
  return parsed.round();
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

List<RadioPowerStep> _powerSteps(Object? value) {
  if (value is! List) return const [];
  final result = <RadioPowerStep>[];
  final seen = <String>{};
  for (final item in value) {
    if (item is! Map) continue;
    try {
      final step = RadioPowerStep.fromJson(Map<String, dynamic>.from(item));
      if (seen.add(step.id)) result.add(step);
    } on FormatException {
      // Invalid capability entries are ignored instead of becoming UI controls.
    }
  }
  result.sort((a, b) => a.nominalMw.compareTo(b.nominalMw));
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
