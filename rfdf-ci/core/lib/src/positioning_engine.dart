import 'dart:math' as math;
import 'models.dart';

class PositioningEngine {
  final Duration maxRangeAge;
  const PositioningEngine({this.maxRangeAge = const Duration(seconds: 2)});

  TargetEstimate estimate({
    required Anchor a,
    required Anchor b,
    RangeMeasurement? rangeAT,
    RangeMeasurement? rangeBT,
    TargetEstimate? previousEstimate,
    int? preferredSide,
    DateTime? now,
  }) {
    final tNow = now ?? DateTime.now();
    if (rangeAT == null || rangeBT == null) {
      return TargetEstimate(
        position: previousEstimate?.position,
        uncertaintyMeters:
            math.max(previousEstimate?.uncertaintyMeters ?? 0, 18),
        geometryQuality:
            previousEstimate?.geometryQuality ?? GeometryQuality.unavailable,
        timestamp: tNow,
        status: EstimateStatus.missingRange,
        branch: previousEstimate?.branch,
        sourceRanges: [
          if (rangeAT != null) rangeAT,
          if (rangeBT != null) rangeBT
        ],
        diagnostics: const {'reason': 'one_or_more_ranges_missing'},
      );
    }
    final ranges = [rangeAT, rangeBT];
    final newestAllowed = tNow.subtract(maxRangeAge);
    if (rangeAT.timestamp.isBefore(newestAllowed) ||
        rangeBT.timestamp.isBefore(newestAllowed)) {
      return TargetEstimate(
        position: previousEstimate?.position,
        uncertaintyMeters:
            math.max(previousEstimate?.uncertaintyMeters ?? 0, 25),
        geometryQuality:
            previousEstimate?.geometryQuality ?? GeometryQuality.unavailable,
        timestamp: tNow,
        status: EstimateStatus.stale,
        branch: previousEstimate?.branch,
        sourceRanges: ranges,
        diagnostics: const {'reason': 'stale_range'},
      );
    }

    final candidates = circleIntersections(
        a.position, rangeAT.rangeMeters, b.position, rangeBT.rangeMeters);
    final geometry = geometryQuality(
        a.position, b.position, rangeAT.rangeMeters, rangeBT.rangeMeters);
    if (candidates.isEmpty) {
      final gap = _circleGap(
          a.position, rangeAT.rangeMeters, b.position, rangeBT.rangeMeters);
      return TargetEstimate(
        position: previousEstimate?.position,
        uncertaintyMeters: math.max(
            30,
            _uncertainty(rangeAT, rangeBT, a.position.distanceTo(b.position),
                    rangeAT.rangeMeters, rangeBT.rangeMeters) +
                gap.abs()),
        geometryQuality: geometry,
        timestamp: tNow,
        status: EstimateStatus.degraded,
        branch: previousEstimate?.branch,
        sourceRanges: ranges,
        diagnostics: {'reason': 'circles_do_not_intersect', 'gap_m': gap},
      );
    }

    final choice = _chooseCandidate(candidates, a.position, b.position,
        previousEstimate?.position, preferredSide);
    final uncertainty = _uncertainty(
        rangeAT,
        rangeBT,
        a.position.distanceTo(b.position),
        rangeAT.rangeMeters,
        rangeBT.rangeMeters);
    if (choice == null) {
      return TargetEstimate(
        position: previousEstimate?.position,
        uncertaintyMeters: math.max(uncertainty, 15),
        geometryQuality: geometry,
        timestamp: tNow,
        status: EstimateStatus.ambiguous,
        branch: previousEstimate?.branch,
        sourceRanges: ranges,
        diagnostics: {
          'reason': 'two_valid_branches',
          'candidate_count': candidates.length
        },
      );
    }
    return TargetEstimate(
      position: choice.$1,
      uncertaintyMeters: uncertainty,
      geometryQuality: geometry,
      timestamp: tNow,
      status: EstimateStatus.ok,
      branch: choice.$2,
      sourceRanges: ranges,
      diagnostics: {'candidate_count': candidates.length},
    );
  }

  static List<MetersPoint> circleIntersections(
      MetersPoint c0, double r0, MetersPoint c1, double r1) {
    final dx = c1.x - c0.x;
    final dy = c1.y - c0.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d == 0 || d > r0 + r1 || d < (r0 - r1).abs()) return const [];
    final x = (r0 * r0 - r1 * r1 + d * d) / (2 * d);
    var h2 = r0 * r0 - x * x;
    if (h2 < -1e-8) return const [];
    h2 = math.max(0, h2);
    final h = math.sqrt(h2);
    final ux = dx / d;
    final uy = dy / d;
    final px = c0.x + x * ux;
    final py = c0.y + x * uy;
    final rx = -uy * h;
    final ry = ux * h;
    final p1 = MetersPoint(px + rx, py + ry);
    if (h < 1e-8) return [p1];
    final p2 = MetersPoint(px - rx, py - ry);
    return [p1, p2];
  }

  static int sideOfLine(MetersPoint a, MetersPoint b, MetersPoint p) {
    final cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    if (cross > 1e-9) return 1;
    if (cross < -1e-9) return -1;
    return 0;
  }

  static (MetersPoint, int)? _chooseCandidate(List<MetersPoint> candidates,
      MetersPoint a, MetersPoint b, MetersPoint? previous, int? preferredSide) {
    if (candidates.length == 1) return (candidates.first, 0);
    if (preferredSide != null && preferredSide != 0) {
      final matching = <(MetersPoint, int)>[];
      for (var i = 0; i < candidates.length; i++) {
        if (sideOfLine(a, b, candidates[i]) == preferredSide) {
          matching.add((candidates[i], i));
        }
      }
      if (matching.length == 1) return matching.first;
      if (matching.length > 1 && previous != null) {
        matching.sort((x, y) =>
            x.$1.distanceTo(previous).compareTo(y.$1.distanceTo(previous)));
        return matching.first;
      }
    }
    if (previous != null) {
      final indexed =
          List.generate(candidates.length, (i) => (candidates[i], i));
      indexed.sort((x, y) =>
          x.$1.distanceTo(previous).compareTo(y.$1.distanceTo(previous)));
      final d0 = indexed[0].$1.distanceTo(previous);
      final d1 = indexed[1].$1.distanceTo(previous);
      if ((d1 - d0).abs() > 1e-6) return indexed.first;
    }
    return null;
  }

  static GeometryQuality geometryQuality(
      MetersPoint a, MetersPoint b, double rA, double rB) {
    final baseline = a.distanceTo(b);
    if (baseline <= 0 || rA <= 0 || rB <= 0) return GeometryQuality.unavailable;
    final cosAngle = ((rA * rA + rB * rB - baseline * baseline) / (2 * rA * rB))
        .clamp(-1.0, 1.0);
    final sinAngle = math.sqrt(math.max(0, 1 - cosAngle * cosAngle));
    if (sinAngle >= 0.65) return GeometryQuality.good;
    if (sinAngle >= 0.30) return GeometryQuality.fair;
    return GeometryQuality.poor;
  }

  static double _uncertainty(RangeMeasurement a, RangeMeasurement b,
      double baseline, double rA, double rB) {
    if (baseline <= 0 || rA <= 0 || rB <= 0) return 999;
    final cosAngle = ((rA * rA + rB * rB - baseline * baseline) / (2 * rA * rB))
        .clamp(-1.0, 1.0);
    final sinAngle = math.sqrt(math.max(0, 1 - cosAngle * cosAngle));
    final geomPenalty = 1 / math.max(0.15, sinAngle);
    final sigma = math.sqrt(
            a.sigmaMeters * a.sigmaMeters + b.sigmaMeters * b.sigmaMeters) /
        math.sqrt(2);
    final qualityPenalty = 1 / math.max(0.25, (a.quality + b.quality) / 2);
    return math.max(1.0, sigma * geomPenalty * qualityPenalty * 1.8);
  }

  static double _circleGap(MetersPoint a, double rA, MetersPoint b, double rB) {
    final d = a.distanceTo(b);
    if (d > rA + rB) return d - rA - rB;
    if (d < (rA - rB).abs()) return (rA - rB).abs() - d;
    return 0;
  }
}
