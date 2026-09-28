enum AdaptiveLinkProfile { reliable, balanced, bulk }

final class LinkQualitySample {
  const LinkQualitySample({
    this.rssiDbm,
    this.lossPercent,
    this.rttMs,
    this.goodputBytesPerSecond,
  });

  final double? rssiDbm;
  final double? lossPercent;
  final double? rttMs;
  final double? goodputBytesPerSecond;
}

final class AdaptiveLinkDecision {
  const AdaptiveLinkDecision({
    required this.profile,
    required this.score,
    required this.reason,
  });

  final AdaptiveLinkProfile profile;
  final double score;
  final String reason;
}

final class AdaptiveLinkPolicy {
  const AdaptiveLinkPolicy._();

  static AdaptiveLinkDecision choose(
    LinkQualitySample sample, {
    AdaptiveLinkProfile? current,
  }) {
    var score = 100.0;
    final reasons = <String>[];

    final loss = sample.lossPercent;
    if (loss != null) {
      final clamped = loss.clamp(0.0, 100.0);
      score -= clamped * 2.2;
      if (clamped >= 10) reasons.add('loss ' + clamped.toStringAsFixed(1) + '%');
    }

    final rtt = sample.rttMs;
    if (rtt != null) {
      if (rtt > 150) score -= ((rtt - 150) / 8).clamp(0, 35);
      if (rtt >= 500) reasons.add('RTT ' + rtt.toStringAsFixed(0) + ' ms');
    }

    final rssi = sample.rssiDbm;
    if (rssi != null) {
      if (rssi < -70) score -= ((-70 - rssi) * 1.5).clamp(0, 35);
      if (rssi <= -90) reasons.add('RSSI ' + rssi.toStringAsFixed(0) + ' dBm');
    }

    score = score.clamp(0.0, 100.0);
    var chosen = score >= 82
        ? AdaptiveLinkProfile.bulk
        : score >= 55
            ? AdaptiveLinkProfile.balanced
            : AdaptiveLinkProfile.reliable;

    if (current == AdaptiveLinkProfile.reliable &&
        chosen != AdaptiveLinkProfile.reliable &&
        score < 65) {
      chosen = AdaptiveLinkProfile.reliable;
    } else if (current == AdaptiveLinkProfile.balanced &&
        chosen == AdaptiveLinkProfile.bulk &&
        score < 88) {
      chosen = AdaptiveLinkProfile.balanced;
    }

    return AdaptiveLinkDecision(
      profile: chosen,
      score: score,
      reason: reasons.isEmpty ? 'link stable' : reasons.join(', '),
    );
  }

  static int recommendedChunkSize(AdaptiveLinkProfile profile) => switch (profile) {
        AdaptiveLinkProfile.reliable => 256,
        AdaptiveLinkProfile.balanced => 1024,
        AdaptiveLinkProfile.bulk => 4096,
      };

  static int recommendedInFlightChunks(AdaptiveLinkProfile profile) =>
      switch (profile) {
        AdaptiveLinkProfile.reliable => 1,
        AdaptiveLinkProfile.balanced => 2,
        AdaptiveLinkProfile.bulk => 4,
      };
}
