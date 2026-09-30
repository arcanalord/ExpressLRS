final class Lr24PeerReachability {
  Lr24PeerReachability({
    this.freshFor = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final Duration freshFor;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  void clear() => _lastSeen.clear();

  void markSeen(String mmId) {
    final clean = mmId.trim();
    if (clean.isEmpty) return;
    _lastSeen[clean] = _now().toUtc();
    _prune();
  }

  bool isFresh(String mmId) {
    _prune();
    return _lastSeen.containsKey(mmId);
  }

  bool get hasFreshPeers {
    _prune();
    return _lastSeen.isNotEmpty;
  }

  Set<String> get freshPeerMmIds {
    _prune();
    return Set<String>.unmodifiable(_lastSeen.keys.toSet());
  }

  int? ageMs(String mmId) {
    _prune();
    final seen = _lastSeen[mmId];
    if (seen == null) return null;
    return _now().toUtc().difference(seen).inMilliseconds;
  }

  void _prune() {
    final cutoff = _now().toUtc().subtract(freshFor);
    _lastSeen.removeWhere((_, seen) => seen.isBefore(cutoff));
  }
}
