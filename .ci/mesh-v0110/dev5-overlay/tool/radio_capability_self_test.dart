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
  }, info: sx);
  if (caps.rangingAvailable) throw StateError('ranging inferred incorrectly');
  if (!caps.rssiAvailable || !caps.supportsMmrp) {
    throw StateError('capability normalization failed');
  }
  if (caps.profileIds.length != 1 || caps.frequencyRanges.length != 1) {
    throw StateError('capability sanitization failed');
  }
  final absentMmrp = RadioCapabilities.fromJson({
    'radioFamily': 'SX1280',
    'profileIds': ['MM-PHY-24-COMMON-v0'],
  });
  if (absentMmrp.supportsMmrp) {
    throw StateError('MMRP must require explicit networkProtocols advertisement');
  }

  print('RADIO_CAPABILITY_DART_PASS');
}
