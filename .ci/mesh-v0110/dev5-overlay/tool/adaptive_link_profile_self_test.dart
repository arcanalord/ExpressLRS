import 'dart:io';

import '../lib/core/adaptive_link_profile.dart';

void main() {
  final good = AdaptiveLinkPolicy.choose(
    const LinkQualitySample(rssiDbm: -55, lossPercent: 0.5, rttMs: 80),
  );
  if (good.profile != AdaptiveLinkProfile.bulk) {
    throw StateError('Good link did not choose bulk');
  }

  final medium = AdaptiveLinkPolicy.choose(
    const LinkQualitySample(rssiDbm: -78, lossPercent: 3, rttMs: 260),
  );
  if (medium.profile != AdaptiveLinkProfile.balanced) {
    throw StateError('Medium link did not choose balanced');
  }

  final poor = AdaptiveLinkPolicy.choose(
    const LinkQualitySample(rssiDbm: -98, lossPercent: 18, rttMs: 700),
  );
  if (poor.profile != AdaptiveLinkProfile.reliable) {
    throw StateError('Poor link did not choose reliable');
  }

  if (AdaptiveLinkPolicy.recommendedChunkSize(AdaptiveLinkProfile.reliable) >=
      AdaptiveLinkPolicy.recommendedChunkSize(AdaptiveLinkProfile.bulk)) {
    throw StateError('Chunk-size policy invalid');
  }

  stdout.writeln('MESH_MESSENGER_ADAPTIVE_LINK_SELF_TEST_PASS');
}
