import 'dart:async';

import 'models.dart';
import 'simulation_source.dart';
import 'source_adapter_v1.dart';

final class SimulationSourceAdapterV1
    implements SourceAdapterV1<MeasurementFrame> {
  @override
  final String sourceId;

  final List<MeasurementFrame> _frames;
  final Duration emitEvery;
  final int heartbeatEvery;
  final StreamController<SourceEventV1<MeasurementFrame>> _events =
      StreamController<SourceEventV1<MeasurementFrame>>.broadcast(sync: true);

  bool _isConnected = false;
  bool _started = false;
  bool _stopRequested = false;
  DateTime? _lastAcceptedTimestamp;
  Future<void>? _pump;

  SimulationSourceAdapterV1(
    Iterable<MeasurementFrame> frames, {
    this.sourceId = 'rfdf-simulation-v1',
    this.emitEvery = Duration.zero,
    this.heartbeatEvery = 10,
  }) : _frames = List<MeasurementFrame>.unmodifiable(frames);

  factory SimulationSourceAdapterV1.fromSource(
    SimulationSource source, {
    String sourceId = 'rfdf-simulation-v1',
    Duration emitEvery = Duration.zero,
    int heartbeatEvery = 10,
    bool injectDisconnect = true,
  }) =>
      SimulationSourceAdapterV1(
        source.generate(injectDisconnect: injectDisconnect),
        sourceId: sourceId,
        emitEvery: emitEvery,
        heartbeatEvery: heartbeatEvery,
      );

  @override
  bool get isConnected => _isConnected;

  bool get isRunning => _started;

  @override
  Stream<SourceEventV1<MeasurementFrame>> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _stopRequested = false;
    _lastAcceptedTimestamp = null;
    _isConnected = true;
    _emit(
      SourceEventType.heartbeat,
      timestamp: _frames.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : _frames.first.timestamp,
      reason: 'connected',
    );
    _pump = _run();
  }

  Future<void> waitUntilComplete() async {
    final pump = _pump;
    if (pump != null) await pump;
  }

  @override
  Future<void> stop() async {
    if (!_started && _pump == null) return;
    _stopRequested = true;
    final pump = _pump;
    if (pump != null) await pump;
  }

  Future<void> _run() async {
    var acceptedData = 0;
    try {
      for (final frame in _frames) {
        if (_stopRequested) break;
        if (emitEvery.inMicroseconds > 0) {
          await Future<void>.delayed(emitEvery);
        }

        if (frame.disconnected) {
          if (_isConnected) {
            _isConnected = false;
            _emit(
              SourceEventType.disconnect,
              timestamp: frame.timestamp,
              data: frame,
              reason: 'source-disconnected',
            );
          }
          continue;
        }

        if (!_isConnected) {
          _isConnected = true;
          _emit(
            SourceEventType.reconnect,
            timestamp: frame.timestamp,
            reason: 'source-reconnected',
          );
        }

        final invalid = _invalidReason(frame);
        if (invalid != null) {
          _emit(
            SourceEventType.error,
            timestamp: frame.timestamp,
            reason: 'invalid:$invalid',
          );
          continue;
        }

        final previous = _lastAcceptedTimestamp;
        if (previous != null && !frame.timestamp.isAfter(previous)) {
          _emit(
            SourceEventType.error,
            timestamp: frame.timestamp,
            reason: 'stale:non-monotonic-timestamp',
          );
          continue;
        }

        _lastAcceptedTimestamp = frame.timestamp;
        acceptedData++;
        _emit(SourceEventType.data, timestamp: frame.timestamp, data: frame);
        if (heartbeatEvery > 0 && acceptedData % heartbeatEvery == 0) {
          _emit(
            SourceEventType.heartbeat,
            timestamp: frame.timestamp,
            reason: 'data-heartbeat',
          );
        }
      }
    } finally {
      final endTimestamp = _lastAcceptedTimestamp ??
          (_frames.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
              : _frames.last.timestamp);
      if (_isConnected) {
        _isConnected = false;
        _emit(
          SourceEventType.disconnect,
          timestamp: endTimestamp,
          reason: _stopRequested ? 'stopped' : 'completed',
        );
      }
      _started = false;
      _pump = null;
    }
  }

  void _emit(
    SourceEventType type, {
    required DateTime timestamp,
    MeasurementFrame? data,
    String? reason,
  }) {
    _events.add(SourceEventV1<MeasurementFrame>(
      type: type,
      timestamp: timestamp,
      data: data,
      reason: reason,
    ));
  }

  String? _invalidReason(MeasurementFrame frame) {
    for (final measurement in [frame.aToT, frame.bToT]) {
      if (measurement == null) continue;
      if (measurement.fromNode.trim().isEmpty ||
          measurement.toNode.trim().isEmpty) {
        return 'empty-node-id';
      }
      if (!measurement.rangeMeters.isFinite || measurement.rangeMeters <= 0) {
        return 'range';
      }
      if (!measurement.sigmaMeters.isFinite || measurement.sigmaMeters < 0) {
        return 'sigma';
      }
      if (!measurement.quality.isFinite ||
          measurement.quality < 0 ||
          measurement.quality > 1) {
        return 'quality';
      }
    }
    return null;
  }
}
