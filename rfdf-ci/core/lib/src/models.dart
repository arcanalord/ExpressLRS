import 'dart:math' as math;

class MetersPoint {
  final double x;
  final double y;
  const MetersPoint(this.x, this.y);

  double distanceTo(MetersPoint other) =>
      math.sqrt((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y));

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

enum AnchorRole { a, b, c }

class Anchor {
  final String id;
  final AnchorRole role;
  final MetersPoint position;
  final DateTime updatedAt;
  const Anchor({
    required this.id,
    required this.role,
    required this.position,
    required this.updatedAt,
  });
}

class RangeMeasurement {
  final String fromNode;
  final String toNode;
  final double rangeMeters;
  final double sigmaMeters;
  final DateTime timestamp;
  final double quality;
  final double? rssi;
  final double? snr;
  final double? rtt;
  final String profileId;

  const RangeMeasurement({
    required this.fromNode,
    required this.toNode,
    required this.rangeMeters,
    required this.sigmaMeters,
    required this.timestamp,
    this.quality = 1.0,
    this.rssi,
    this.snr,
    this.rtt,
    this.profileId = 'sim',
  });
}

abstract class MeasurementFrame {
  final DateTime timestamp;
  final RangeMeasurement? aToT;
  final RangeMeasurement? bToT;
  final bool disconnected;

  const MeasurementFrame({
    required this.timestamp,
    required this.aToT,
    required this.bToT,
    required this.disconnected,
  });
}

enum GeometryQuality { good, fair, poor, unavailable }

enum EstimateStatus { ok, ambiguous, degraded, stale, missingRange }

class TargetEstimate {
  final MetersPoint? position;
  final double uncertaintyMeters;
  final GeometryQuality geometryQuality;
  final DateTime timestamp;
  final EstimateStatus status;
  final int? branch;
  final List<RangeMeasurement> sourceRanges;
  final Map<String, Object?> diagnostics;

  const TargetEstimate({
    required this.position,
    required this.uncertaintyMeters,
    required this.geometryQuality,
    required this.timestamp,
    required this.status,
    required this.branch,
    required this.sourceRanges,
    required this.diagnostics,
  });

  bool get hasPosition => position != null;
}
