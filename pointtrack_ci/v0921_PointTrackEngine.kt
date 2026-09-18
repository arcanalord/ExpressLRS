package com.pointtrack.core

import kotlin.math.roundToInt
import kotlin.system.measureNanoTime

class PointTrackEngine(private val config: EngineConfig = EngineConfig()) {
    private val detector = PointDetector(config.detector)
    private val hotPixels = HotPixelMap(config.hotPixels)
    private val staticClutter = StaticClutterMap(config.staticClutter)
    private val tracker = PointTracker(config.tracker)

    fun reset() {
        hotPixels.reset(); staticClutter.reset(); tracker.reset()
    }

    fun hotPixelLearnedCount(): Int = hotPixels.learnedCount()
    fun staticClutterLearnedCount(): Int = staticClutter.learnedCount()

    private fun roiAround(cx: Double, cy: Double, half: Int): RectI = RectI(
        cx.roundToInt() - half, cy.roundToInt() - half,
        cx.roundToInt() + half, cy.roundToInt() + half,
    )

    fun processFrame(
        frame: GrayFrame,
        motionHint: MotionHint? = null,
        command: TrackerCommand = TrackerCommand.None,
    ): EngineResult {
        if (command is TrackerCommand.Release) {
            val track = tracker.release(frame.timestampNs)
            return EngineResult(track, ScanMode.SKIPPED, 0, 0, staticClutter.learnedCount(), 0.0, 0.0)
        }

        val before = tracker.estimate(frame.timestampNs)
        var scanMode = ScanMode.SKIPPED
        var roi: RectI? = null
        if (command is TrackerCommand.Lock) {
            val half = command.radiusPx.coerceAtLeast(6.0).roundToInt()
            roi = roiAround(command.x, command.y, half)
            scanMode = ScanMode.LOCK_ROI
        } else if (before.valid) {
            val (px, py) = tracker.predictedPosition(frame.timestampNs)
            when (before.state) {
                TrackState.INIT, TrackState.LOCKED -> {
                    roi = roiAround(px, py, config.tracker.lockedRoiHalfSizePx)
                    scanMode = ScanMode.TRACK_ROI
                }
                TrackState.COAST -> {
                    roi = roiAround(px, py, config.tracker.coastRoiHalfSizePx)
                    scanMode = ScanMode.EXPANDED_ROI
                }
                TrackState.SEARCH, TrackState.REACQUIRE -> {
                    val h = config.tracker.searchRoiHalfSizePx
                    if (2 * h + 1 >= frame.width || 2 * h + 1 >= frame.height) {
                        roi = null; scanMode = ScanMode.FULL_FRAME
                    } else {
                        roi = roiAround(px, py, h); scanMode = ScanMode.EXPANDED_ROI
                    }
                }
                else -> Unit
            }
        }

        if (scanMode == ScanMode.SKIPPED) {
            return EngineResult(before, scanMode, 0, 0, staticClutter.learnedCount(), 0.0, 0.0)
        }

        lateinit var evidence: List<Measurement>
        val detectorNs = measureNanoTime { evidence = detector.detectEvidence(frame, roi) }
        hotPixels.update(evidence, frame.width, frame.height)

        var rejected = 0
        val transform = motionHint?.transform ?: FrameTransform2D()
        val validEvidence = ArrayList<Measurement>(evidence.size)
        for (m in evidence) {
            if (hotPixels.isHardDefectShape(m) || hotPixels.isHot(m)) {
                rejected++
            } else {
                validEvidence += transform.transform(m)
            }
        }
        staticClutter.update(validEvidence)

        var result = before
        val trackerNs = measureNanoTime {
            if (command is TrackerCommand.Lock) {
                val r2 = command.radiusPx * command.radiusPx
                val best = validEvidence
                    .map { it to ((it.sourceX - command.x) * (it.sourceX - command.x) + (it.sourceY - command.y) * (it.sourceY - command.y)) }
                    .filter { it.second <= r2 }
                    .minWithOrNull(compareBy<Pair<Measurement, Double>> { it.second }.thenByDescending { it.first.snr })
                    ?.first
                if (best != null) {
                    tracker.initialize(transform.transform(best.copy(x = best.sourceX, y = best.sourceY)), frame.timestampNs)
                    result = tracker.estimate(frame.timestampNs)
                } else {
                    result = before
                }
            } else {
                result = tracker.step(validEvidence, frame.timestampNs)
            }
        }

        return EngineResult(
            track = result,
            scanMode = scanMode,
            evidenceCandidates = evidence.size,
            hotPixelsRejected = rejected,
            staticClutterLearned = staticClutter.learnedCount(),
            detectorMs = detectorNs / 1e6,
            trackerMs = trackerNs / 1e6,
        )
    }
}
