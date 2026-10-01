import 'dart:io';

import '../lib/src/models.dart';
import '../lib/src/rfdf_controller.dart';
import '../lib/src/simulation_source.dart';
import '../lib/src/simulation_source_adapter_v1.dart';
import '../lib/src/source_adapter_v1.dart';

int passed = 0;
final failures = <String>[];

void check(String name, bool ok, [Object? details]) {
  if (ok) {
    passed++;
    stdout.writeln('PASS $name');
  } else {
    failures.add('$name${details == null ? '' : ': $details'}');
    stderr.writeln('FAIL $name ${details ?? ''}');
  }
}

RangeMeasurement range(String from, double value, DateTime time) =>
    RangeMeasurement(
      fromNode: from,
      toNode: 'T',
      rangeMeters: value,
      sigmaMeters: 2,
      timestamp: time,
      quality: .95,
    );

Future<void> main() async {
  final now = DateTime.utc(2026, 10, 1, 20);
  final a = Anchor(
    id: 'A',
    role: AnchorRole.a,
    position: const MetersPoint(0, 0),
    updatedAt: now,
  );
  final b = Anchor(
    id: 'B',
    role: AnchorRole.b,
    position: const MetersPoint(100, 0),
    updatedAt: now,
  );
  const truth = MetersPoint(50, 40);
  final ra = a.position.distanceTo(truth);
  final rb = b.position.distanceTo(truth);

  final frames = <MeasurementFrame>[
    SimulationFrame(
      index: 0,
      timestamp: now,
      trueTarget: truth,
      aToT: range('A', ra, now),
      bToT: range('B', rb, now),
      disconnected: false,
    ),
    SimulationFrame(
      index: 1,
      timestamp: now.add(const Duration(milliseconds: 200)),
      trueTarget: truth,
      aToT: range('A', ra, now.add(const Duration(milliseconds: 200))),
      bToT: range('B', rb, now.add(const Duration(milliseconds: 200))),
      disconnected: false,
    ),
    SimulationFrame(
      index: 2,
      timestamp: now.add(const Duration(milliseconds: 400)),
      trueTarget: truth,
      aToT: null,
      bToT: null,
      disconnected: true,
    ),
    SimulationFrame(
      index: 3,
      timestamp: now.add(const Duration(milliseconds: 600)),
      trueTarget: truth,
      aToT: range('A', ra, now.add(const Duration(milliseconds: 600))),
      bToT: range('B', rb, now.add(const Duration(milliseconds: 600))),
      disconnected: false,
    ),
    SimulationFrame(
      index: 4,
      timestamp: now.add(const Duration(milliseconds: 500)),
      trueTarget: truth,
      aToT: range('A', ra, now.add(const Duration(milliseconds: 500))),
      bToT: range('B', rb, now.add(const Duration(milliseconds: 500))),
      disconnected: false,
    ),
    SimulationFrame(
      index: 5,
      timestamp: now.add(const Duration(milliseconds: 800)),
      trueTarget: truth,
      aToT: RangeMeasurement(
        fromNode: 'A',
        toNode: 'T',
        rangeMeters: -1,
        sigmaMeters: 2,
        timestamp: now.add(const Duration(milliseconds: 800)),
      ),
      bToT: range('B', rb, now.add(const Duration(milliseconds: 800))),
      disconnected: false,
    ),
    SimulationFrame(
      index: 6,
      timestamp: now.add(const Duration(milliseconds: 1000)),
      trueTarget: truth,
      aToT: range('A', ra, now.add(const Duration(milliseconds: 1000))),
      bToT: range('B', rb, now.add(const Duration(milliseconds: 1000))),
      disconnected: false,
    ),
  ];

  final lifecycle = <SourceEventV1<MeasurementFrame>>[];
  final adapter = SimulationSourceAdapterV1(frames, heartbeatEvery: 2);
  final sub = adapter.events.listen(lifecycle.add);
  await adapter.start();
  await adapter.waitUntilComplete();
  await sub.cancel();

  check(
    'connect_state',
    lifecycle.first.type == SourceEventType.heartbeat &&
        lifecycle.first.reason == 'connected',
  );
  check(
    'data',
    lifecycle.where((e) => e.type == SourceEventType.data).length == 4,
  );
  check(
    'heartbeat',
    lifecycle.any((e) =>
        e.type == SourceEventType.heartbeat &&
        e.reason == 'data-heartbeat'),
  );
  check(
    'disconnect',
    lifecycle.any((e) =>
        e.type == SourceEventType.disconnect &&
        e.reason == 'source-disconnected'),
  );
  check(
    'reconnect',
    lifecycle.any((e) =>
        e.type == SourceEventType.reconnect &&
        e.reason == 'source-reconnected'),
  );
  check(
    'stale_rejected',
    lifecycle.any((e) =>
        e.type == SourceEventType.error &&
        (e.reason ?? '').startsWith('stale:')),
  );
  check(
    'invalid_rejected',
    lifecycle.any((e) =>
        e.type == SourceEventType.error &&
        (e.reason ?? '').startsWith('invalid:')),
  );
  check(
    'completion',
    lifecycle.any((e) =>
        e.type == SourceEventType.disconnect && e.reason == 'completed'),
  );
  check('not_connected_after_completion', !adapter.isConnected);

  final sim = SimulationSource(
    a: a,
    b: b,
    seed: 26092026,
    noiseSigmaMeters: 3.5,
    lossRate: .15,
    frameCount: 160,
  );
  final controller = RfdfController()..setAnchors(a, b, preferredSide: 1);
  final runtimeEvents = <SourceEventV1<MeasurementFrame>>[];
  final runtimeAdapter = SimulationSourceAdapterV1.fromSource(
    sim,
    heartbeatEvery: 20,
  );
  final runtimeSub = runtimeAdapter.events.listen((event) {
    runtimeEvents.add(event);
    if ((event.type == SourceEventType.data ||
            event.type == SourceEventType.disconnect) &&
        event.data != null) {
      controller.consume(event.data!);
    }
  });
  await runtimeAdapter.start();
  await runtimeAdapter.waitUntilComplete();
  await runtimeSub.cancel();

  check('controller_frames', controller.receivedFrames > 100,
      controller.receivedFrames);
  check(
    'controller_disconnect_seen',
    runtimeEvents.any((e) =>
        e.type == SourceEventType.disconnect &&
        e.reason == 'source-disconnected'),
  );
  check(
    'controller_reconnect_seen',
    runtimeEvents.any((e) => e.type == SourceEventType.reconnect),
  );
  check(
    'controller_recovers_without_restart',
    controller.estimate?.status == EstimateStatus.ok &&
        controller.track.length > 10,
    controller.diagnostics(),
  );

  stdout.writeln(
      'SOURCE_ADAPTER_RUNTIME_GATE ${failures.isEmpty ? 'PASS' : 'FAIL'} passed=$passed failed=${failures.length}');
  if (failures.isNotEmpty) exitCode = 1;
}
