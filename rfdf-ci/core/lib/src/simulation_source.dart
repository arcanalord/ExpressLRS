import 'dart:math' as math;
import 'models.dart';

class SimulationFrame extends MeasurementFrame {
  final int index;
  final MetersPoint trueTarget;

  const SimulationFrame({
    required this.index,
    required super.timestamp,
    required this.trueTarget,
    required super.aToT,
    required super.bToT,
    required super.disconnected,
  });
}

class _Rng {
  int state;
  _Rng(this.state);

  double next() {
    state = (1664525 * state + 1013904223) & 0xffffffff;
    return state / 0x100000000;
  }

  double gaussian() {
    final u1 = math.max(next(), 1e-12);
    final u2 = next();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

class SimulationSource {
  final Anchor a;
  final Anchor b;
  final int seed;
  final double noiseSigmaMeters;
  final double lossRate;
  final int frameCount;
  final Duration step;

  SimulationSource({
    required this.a,
    required this.b,
    this.seed = 26092026,
    this.noiseSigmaMeters = 4,
    this.lossRate = 0.15,
    this.frameCount = 120,
    this.step = const Duration(milliseconds: 200),
  });

  List<SimulationFrame> generate({bool injectDisconnect = true}) {
    final rng = _Rng(seed);
    final start = DateTime.utc(2026, 9, 26, 18);
    final out = <SimulationFrame>[];
    for (var i = 0; i < frameCount; i++) {
      final t = i / math.max(1, frameCount - 1);
      final target =
          MetersPoint(25 + 120 * t, 45 + 18 * math.sin(t * math.pi * 2));
      final disconnected = injectDisconnect &&
          i >= (frameCount * .56).floor() &&
          i < (frameCount * .66).floor();
      final sigma =
          (i >= (frameCount * .35).floor() && i < (frameCount * .55).floor())
              ? noiseSigmaMeters * 2.5
              : noiseSigmaMeters;

      RangeMeasurement? mk(Anchor anchor, String from) {
        if (disconnected || rng.next() < lossRate) return null;
        final trueRange = anchor.position.distanceTo(target);
        return RangeMeasurement(
          fromNode: from,
          toNode: 'T',
          rangeMeters: math.max(0.1, trueRange + rng.gaussian() * sigma),
          sigmaMeters: sigma,
          timestamp: start.add(step * i),
          quality: sigma > noiseSigmaMeters ? 0.55 : 0.95,
          rssi: -62 - 0.06 * trueRange,
          snr: 8 - 0.02 * trueRange,
          rtt: 8 + 0.03 * trueRange,
          profileId: 'SIM-FLRC',
        );
      }

      out.add(SimulationFrame(
        index: i,
        timestamp: start.add(step * i),
        trueTarget: target,
        aToT: mk(a, 'A'),
        bToT: mk(b, 'B'),
        disconnected: disconnected,
      ));
    }
    return out;
  }
}
