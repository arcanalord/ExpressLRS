import '../lib/platform/radio_capability_contract.dart';

void main() {
  final sx = RadioInfo.fromJson({'radioFamily': 'SX1280', 'boardId': 'ep2'});
  final caps = RadioCapabilities.fromJson({
    'radioFamily': 'SX1280',
    'profileIds': ['A', 'A'],
    'networkProtocols': ['MMRP/1'],
    'frequencyRanges': [
      [2500, 2400],
      [2400, 2500],
    ],
    'rssiAvailable': true,
    'rangingAvailable': false,
    'maxPayload': 512,
    'powerControlAvailable': true,
    'powerControlVersion': 1,
    'powerUnit': 'mW',
    'powerCalibrationSource': 'STOCK_TARGET',
    'autoPowerAvailable': true,
    'powerSteps': [
      {
        'id': 'P100',
        'nominalMw': 100,
        'radiatedPowerCalibrated': true,
        'normalUiRecommended': true,
        'autoEligible': true,
      },
      {
        'id': 'P250',
        'nominalMw': 250,
        'radiatedPowerCalibrated': true,
        'normalUiRecommended': true,
        'autoEligible': true,
      },
      {
        'id': 'P50',
        'nominalMw': 50,
        'radiatedPowerCalibrated': false,
        'normalUiRecommended': false,
        'autoEligible': false,
      },
    ],
  }, info: sx);
  if (caps.rangingAvailable) throw StateError('ranging inferred incorrectly');
  if (!caps.rssiAvailable || !caps.supportsMmrp) {
    throw StateError('capability normalization failed');
  }
  if (caps.profileIds.length != 1 || caps.frequencyRanges.length != 1) {
    throw StateError('capability sanitization failed');
  }
  if (!caps.supports('power') || caps.selectablePowerSteps.length != 2) {
    throw StateError('power capability normalization failed');
  }
  final defaultPower = caps.selectPowerStep(meshDefaultRequestedPowerMw);
  if (defaultPower == null ||
      !defaultPower.exact ||
      defaultPower.actualMw != 100 ||
      defaultPower.step.id != 'P100') {
    throw StateError('100 mW default selection failed');
  }
  final fallback = caps.selectPowerStep(180);
  if (fallback == null ||
      fallback.exact ||
      fallback.actualMw != 100 ||
      fallback.step.id != 'P100') {
    throw StateError('safe lower power fallback failed');
  }
  final highOnly = RadioCapabilities.fromJson({
    'powerControlAvailable': true,
    'powerSteps': [
      {
        'id': 'P250',
        'nominalMw': 250,
        'radiatedPowerCalibrated': true,
        'normalUiRecommended': true,
        'autoEligible': true,
      },
    ],
  });
  if (highOnly.selectPowerStep(100)?.actualMw != 250) {
    throw StateError('device-minimum fallback failed');
  }
  final absentMmrp = RadioCapabilities.fromJson({
    'radioFamily': 'SX1280',
    'profileIds': ['MM-PHY-24-COMMON-v0'],
  });
  if (absentMmrp.supportsMmrp) {
    throw StateError(
      'MMRP must require explicit networkProtocols advertisement',
    );
  }

  print('RADIO_CAPABILITY_DART_PASS');
}
