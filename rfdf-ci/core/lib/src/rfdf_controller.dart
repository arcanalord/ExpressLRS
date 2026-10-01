import 'models.dart';
import 'positioning_engine.dart';

enum RfdfState {
  idle,
  settingAnchors,
  ready,
  ranging,
  degraded,
  recovering,
  stopped,
  error
}

class RfdfController {
  final PositioningEngine engine;
  Anchor? a;
  Anchor? b;
  int? preferredSide;
  RfdfState state = RfdfState.idle;
  TargetEstimate? estimate;
  final List<MetersPoint> track = [];
  RangeMeasurement? lastA;
  RangeMeasurement? lastB;
  int receivedFrames = 0;
  int missingFrames = 0;
  bool _wasDisconnected = false;

  RfdfController({PositioningEngine? engine})
      : engine = engine ?? const PositioningEngine();

  void setAnchors(Anchor a, Anchor b, {int preferredSide = 1}) {
    this.a = a;
    this.b = b;
    this.preferredSide = preferredSide;
    state = RfdfState.ready;
  }

  void consume(MeasurementFrame frame) {
    if (a == null || b == null) {
      state = RfdfState.error;
      return;
    }
    receivedFrames++;
    if (frame.aToT != null) lastA = frame.aToT;
    if (frame.bToT != null) lastB = frame.bToT;
    if (frame.aToT == null || frame.bToT == null) missingFrames++;

    if (frame.disconnected) {
      _wasDisconnected = true;
      state = RfdfState.degraded;
    } else if (_wasDisconnected) {
      state = RfdfState.recovering;
      _wasDisconnected = false;
    } else {
      state = RfdfState.ranging;
    }

    estimate = engine.estimate(
      a: a!,
      b: b!,
      rangeAT: frame.aToT,
      rangeBT: frame.bToT,
      previousEstimate: estimate,
      preferredSide: preferredSide,
      now: frame.timestamp,
    );
    if (estimate?.status != EstimateStatus.ok) state = RfdfState.degraded;
    if (estimate?.position != null && estimate?.status == EstimateStatus.ok) {
      final p = estimate!.position!;
      if (track.isEmpty || track.last.distanceTo(p) < 80) track.add(p);
    }
  }

  Map<String, Object?> diagnostics() => {
        'state': state.name,
        'receivedFrames': receivedFrames,
        'missingFrames': missingFrames,
        'lossObserved':
            receivedFrames == 0 ? 0 : missingFrames / receivedFrames,
        'estimateStatus': estimate?.status.name,
        'uncertaintyMeters': estimate?.uncertaintyMeters,
        'geometryQuality': estimate?.geometryQuality.name,
        'trackPoints': track.length,
      };
}
