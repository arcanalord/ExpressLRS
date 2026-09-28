enum TransportClass {
  internetRelay,
  lan,
  wifiDirect,
  radio,
  meshtastic,
  futureFastRadio,
}

final class TransportCapabilities {
  const TransportCapabilities({
    required this.transportId,
    required this.transportClass,
    required this.available,
    this.validatedInternet = false,
    this.metered = false,
    this.supportsText = true,
    this.supportsAttachments = false,
    this.supportsBinary = true,
    this.estimatedThroughputBps,
    this.estimatedRttMs,
    this.healthScore = 100,
  });

  final String transportId;
  final TransportClass transportClass;
  final bool available;
  final bool validatedInternet;
  final bool metered;
  final bool supportsText;
  final bool supportsAttachments;
  final bool supportsBinary;
  final int? estimatedThroughputBps;
  final int? estimatedRttMs;
  final int healthScore;

  bool supportsClass(String messageClass) {
    if (messageClass == 'text' || messageClass == 'map_point') {
      return supportsText;
    }
    if (messageClass == 'file' ||
        messageClass == 'photo' ||
        messageClass == 'voice') {
      return supportsAttachments;
    }
    return supportsBinary;
  }

  bool get isInternetUsable =>
      transportClass != TransportClass.internetRelay || validatedInternet;
}

final class RoutePolicy {
  const RoutePolicy({
    this.allowMetered = true,
    this.allowInternet = true,
    this.allowLan = true,
    this.allowRadio = true,
    this.preferUnmeteredForAttachments = true,
  });

  final bool allowMetered;
  final bool allowInternet;
  final bool allowLan;
  final bool allowRadio;
  final bool preferUnmeteredForAttachments;
}

final class RoutePlan {
  const RoutePlan({
    required this.messageId,
    required this.messageClass,
    required this.candidates,
  });

  final String messageId;
  final String messageClass;
  final List<TransportCapabilities> candidates;

  TransportCapabilities? get primary =>
      candidates.isEmpty ? null : candidates.first;
  bool get hasRoute => candidates.isNotEmpty;
}

final class M12TransportRouter {
  const M12TransportRouter();

  RoutePlan plan({
    required String messageId,
    required String messageClass,
    required Iterable<TransportCapabilities> transports,
    RoutePolicy policy = const RoutePolicy(),
  }) {
    final candidates = transports
        .where((item) => _allowed(item, messageClass, policy))
        .toList(growable: false)
      ..sort((a, b) => _rank(
        b,
        messageClass: messageClass,
        policy: policy,
      ).compareTo(_rank(
        a,
        messageClass: messageClass,
        policy: policy,
      )));
    return RoutePlan(
      messageId: messageId,
      messageClass: messageClass,
      candidates: List.unmodifiable(candidates),
    );
  }

  bool _allowed(
    TransportCapabilities item,
    String messageClass,
    RoutePolicy policy,
  ) {
    if (!item.available || !item.isInternetUsable) return false;
    if (!item.supportsClass(messageClass)) return false;
    if (item.metered && !policy.allowMetered) return false;
    return switch (item.transportClass) {
      TransportClass.internetRelay => policy.allowInternet,
      TransportClass.lan || TransportClass.wifiDirect => policy.allowLan,
      TransportClass.radio ||
      TransportClass.meshtastic ||
      TransportClass.futureFastRadio => policy.allowRadio,
    };
  }

  int _rank(
    TransportCapabilities item, {
    required String messageClass,
    required RoutePolicy policy,
  }) {
    var score = item.healthScore.clamp(0, 100) * 100;
    score += switch (item.transportClass) {
      TransportClass.internetRelay => 6000,
      TransportClass.lan || TransportClass.wifiDirect => 5000,
      TransportClass.futureFastRadio => 4000,
      TransportClass.radio => 3000,
      TransportClass.meshtastic => 2000,
    };

    final attachment = messageClass == 'file' ||
        messageClass == 'photo' ||
        messageClass == 'voice';
    if (attachment &&
        policy.preferUnmeteredForAttachments &&
        !item.metered) {
      score += 2500;
    }
    if (item.metered) score -= 1000;
    if (item.estimatedThroughputBps != null) {
      score += (item.estimatedThroughputBps! ~/ 1000).clamp(0, 5000);
    }
    if (item.estimatedRttMs != null) {
      score -= item.estimatedRttMs!.clamp(0, 2000);
    }
    return score;
  }
}
