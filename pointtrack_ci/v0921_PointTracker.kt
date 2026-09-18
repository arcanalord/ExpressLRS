package com.pointtrack.core

import kotlin.math.hypot

class PointTracker(private val config: TrackerConfig = TrackerConfig()) {
    private var state = TrackState.AIM
    private var valid = false
    private var x = 0.0
    private var y = 0.0
    private var vx = 0.0
    private var vy = 0.0
    private var lastTimestampNs = 0L
    private var hits = 0
    private var missed = 0
    private var reacquireHits = 0
    private var confidence = 0.0

    fun reset() {
        state = TrackState.AIM
        valid = false
        x = 0.0; y = 0.0; vx = 0.0; vy = 0.0
        lastTimestampNs = 0L; hits = 0; missed = 0; reacquireHits = 0; confidence = 0.0
    }

    fun release(timestampNs: Long): TrackingResult {
        reset()
        return estimate(timestampNs)
    }

    fun initialize(seed: Measurement, timestampNs: Long) {
        x = seed.x; y = seed.y; vx = 0.0; vy = 0.0
        lastTimestampNs = timestampNs
        hits = 1; missed = 0; reacquireHits = 0
        confidence = 0.35
        state = TrackState.INIT
        valid = true
    }

    fun estimate(timestampNs: Long = lastTimestampNs): TrackingResult = TrackingResult(
        state = state,
        valid = valid,
        timestampNs = timestampNs,
        x = x, y = y, vx = vx, vy = vy,
        missedFrames = missed,
        confidence = confidence.coerceIn(0.0, 1.0),
    )

    fun predictedPosition(timestampNs: Long): Pair<Double, Double> {
        if (!valid || lastTimestampNs == 0L) return x to y
        val dt = ((timestampNs - lastTimestampNs) * 1e-9).coerceIn(config.minDtSeconds, config.maxDtSeconds)
        return (x + vx * dt) to (y + vy * dt)
    }

    fun step(measurements: List<Measurement>, timestampNs: Long): TrackingResult {
        if (!valid) return estimate(timestampNs)
        val dt = if (lastTimestampNs == 0L) config.minDtSeconds
        else ((timestampNs - lastTimestampNs) * 1e-9).coerceIn(config.minDtSeconds, config.maxDtSeconds)
        val px = x + vx * dt
        val py = y + vy * dt
        val baseGate = when (state) {
            TrackState.INIT -> config.initGatePx
            TrackState.LOCKED -> config.lockedGatePx
            TrackState.COAST -> config.coastGatePx
            TrackState.SEARCH, TrackState.REACQUIRE -> config.searchGatePx
            else -> config.searchGatePx
        }
        val speedPad = hypot(vx, vy) * dt * config.velocityGateScale
        val gate = (baseGate + speedPad).coerceAtMost(config.maxDynamicGatePx)
        val best = measurements
            .map { it to hypot(it.x - px, it.y - py) }
            .filter { it.second <= gate }
            .minWithOrNull(compareBy<Pair<Measurement, Double>> { it.second }.thenByDescending { it.first.snr })
            ?.first

        if (best != null) {
            val wasMissing = missed > 0 || state == TrackState.SEARCH || state == TrackState.COAST || state == TrackState.REACQUIRE
            val rx = best.x - px
            val ry = best.y - py
            x = px + config.alpha * rx
            y = py + config.alpha * ry
            vx += config.beta * rx / dt
            vy += config.beta * ry / dt
            hits++
            missed = 0
            if (wasMissing) {
                reacquireHits++
                state = if (reacquireHits >= config.reacquireConfirmHits) TrackState.LOCKED else TrackState.REACQUIRE
                if (state == TrackState.LOCKED) reacquireHits = 0
            } else {
                state = if (hits >= config.lockAfterHits) TrackState.LOCKED else TrackState.INIT
            }
            confidence = (confidence + 0.16 + 0.01 * best.snr.coerceAtMost(10.0)).coerceAtMost(1.0)
            lastTimestampNs = timestampNs
            return TrackingResult(
                state = state, valid = true, timestampNs = timestampNs,
                x = x, y = y, vx = vx, vy = vy,
                measuredThisFrame = true,
                measurementX = best.x, measurementY = best.y,
                predictedX = px, predictedY = py,
                missedFrames = 0, confidence = confidence,
            )
        }

        x = px; y = py
        missed++
        reacquireHits = 0
        state = when {
            missed <= config.maxCoastFrames -> TrackState.COAST
            missed <= config.maxSearchFrames -> TrackState.SEARCH
            else -> TrackState.LOST
        }
        confidence = (confidence - if (state == TrackState.COAST) 0.06 else 0.12).coerceAtLeast(0.0)
        if (state == TrackState.LOST) valid = false
        lastTimestampNs = timestampNs
        return TrackingResult(
            state = state, valid = valid, timestampNs = timestampNs,
            x = x, y = y, vx = vx, vy = vy,
            measuredThisFrame = false,
            predictedX = px, predictedY = py,
            missedFrames = missed, confidence = confidence,
        )
    }
}
