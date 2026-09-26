package club.fpv.real0.core

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class BoxF(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    fun width() = right - left
    fun height() = bottom - top
    fun centerX() = (left + right) * 0.5f
    fun centerY() = (top + bottom) * 0.5f
    fun translated(dx: Float, dy: Float) = BoxF(left + dx, top + dy, right + dx, bottom + dy)
    fun scaledAboutCenter(scale: Float): BoxF {
        val hw = width() * scale * 0.5f
        val hh = height() * scale * 0.5f
        return BoxF(centerX() - hw, centerY() - hh, centerX() + hw, centerY() + hh)
    }
}

interface GrayFrame {
    val width: Int
    val height: Int
    val timestampNs: Long get() = 0L
    fun gray(x: Int, y: Int): Float
}

enum class CoreTrackState { IDLE, READY, TRACKING, UNCERTAIN, LOST, SEARCHING, REACQUIRED }

data class CoreTrackerResult(
    val state: CoreTrackState,
    val measuredBox: BoxF?,
    val predictedBox: BoxF?,
    val quality: Float,
    val processingMs: Float,
    val reason: String
)

class NccTrackerCore {
    private val model = TargetModelCore()
    private val gate = QualityGateCore()
    private val reacquire = ReacquireCore()

    private var measured: BoxF? = null
    private var trusted: BoxF? = null
    private var lastKnown: BoxF? = null
    private var predicted: BoxF? = null
    // Pixels per second. Prediction becomes frame-gap aware when timestampNs is supplied.
    private var vx = 0f
    private var vy = 0f
    private var lastTimestampNs = 0L
    private var state = CoreTrackState.IDLE

    val policy: String get() = model.policy
    val modelUpdates: Int get() = model.updates
    val modelRestores: Int get() = model.restores

    fun reset() {
        model.reset()
        gate.reset()
        reacquire.reset()
        measured = null
        trusted = null
        lastKnown = null
        predicted = null
        vx = 0f
        vy = 0f
        lastTimestampNs = 0L
        state = CoreTrackState.IDLE
    }

    fun init(frame: GrayFrame, initial: BoxF) {
        reset()
        val b = clamp(initial, frame.width, frame.height)
        val d = descriptor(frame, b) ?: return
        model.init(d)
        measured = b
        trusted = b
        lastKnown = b
        predicted = b
        lastTimestampNs = frame.timestampNs
        state = CoreTrackState.TRACKING
    }

    fun update(frame: GrayFrame): CoreTrackerResult {
        val t0 = System.nanoTime()
        val dt = deltaSeconds(frame.timestampNs)
        val current = measured
        if (current != null) {
            val searchBase = predicted ?: current
            val best = scanLocal(frame, searchBase)
            val score = best?.score ?: -1f
            val next = gate.classify(score)
            val quality = quality(score)

            if (best == null || next == CoreTrackState.LOST) {
                // Weak candidates must never become the new trusted geometry.
                val anchor = trusted ?: current
                lastKnown = anchor
                measured = null
                state = CoreTrackState.LOST
                model.restore()
                predicted = clamp(anchor.translated(vx * dt, vy * dt), frame.width, frame.height)
                vx *= 0.96f
                vy *= 0.96f
                return result(quality, t0, "local lost; trusted geometry restored")
            }

            if (next == CoreTrackState.UNCERTAIN) {
                // Keep the last trusted measurement and velocity source.
                val anchor = trusted ?: current
                measured = anchor
                state = CoreTrackState.UNCERTAIN
                predicted = clamp(anchor.translated(vx * dt, vy * dt), frame.width, frame.height)
                vx *= 0.985f
                vy *= 0.985f
                return result(quality, t0, "uncertain; trusted hold")
            }

            val prev = trusted ?: current
            measured = best.box
            trusted = best.box
            lastKnown = best.box
            val safeDt = dt.coerceAtLeast(1f / 120f)
            val rawVx = (best.box.centerX() - prev.centerX()) / safeDt
            val rawVy = (best.box.centerY() - prev.centerY()) / safeDt
            vx = 0.60f * vx + 0.40f * rawVx
            vy = 0.60f * vy + 0.40f * rawVy
            predicted = clamp(best.box.translated(vx * dt, vy * dt), frame.width, frame.height)
            state = CoreTrackState.TRACKING
            if (score >= 0.72f) model.update(best.desc, score)
            return result(quality, t0, "local trusted tracking")
        }

        val trustedBase = trusted ?: lastKnown
        val base = predicted ?: trustedBase
        if (base == null || trustedBase == null) {
            return CoreTrackerResult(CoreTrackState.IDLE, null, null, 0f, 0f, "not initialized")
        }

        predicted = clamp(base.translated(vx * dt, vy * dt), frame.width, frame.height)
        vx *= 0.96f
        vy *= 0.96f
        val reacq = reacquire.search(frame, predicted ?: base, trustedBase, model)
        val q = quality(reacq.score)
        if (reacq.confirmed && reacq.box != null) {
            measured = reacq.box
            trusted = reacq.box
            lastKnown = reacq.box
            predicted = reacq.box
            vx = 0f
            vy = 0f
            gate.reset()
            state = CoreTrackState.REACQUIRED
            // Do not poison the adaptive model on the reacquire frame.
            return result(q, t0, "staged reacquired; model held")
        }
        state = CoreTrackState.SEARCHING
        return result(q, t0, "staged searching")
    }

    private fun deltaSeconds(timestampNs: Long): Float {
        val dt = if (timestampNs > 0L && lastTimestampNs > 0L) {
            ((timestampNs - lastTimestampNs) / 1e9).toFloat().coerceIn(1f / 120f, 0.40f)
        } else {
            1f / 30f
        }
        if (timestampNs > 0L) lastTimestampNs = timestampNs
        return dt
    }

    private fun result(quality: Float, t0: Long, reason: String) = CoreTrackerResult(
        state = state,
        measuredBox = measured,
        predictedBox = predicted,
        quality = quality,
        processingMs = (System.nanoTime() - t0) / 1e6f,
        reason = reason
    )

    private fun scanLocal(frame: GrayFrame, base: BoxF): Candidate? {
        var best: Candidate? = null
        val rx = max(24f, base.width() * 1.30f)
        val ry = max(18f, base.height() * 1.30f)
        val step = max(2, (min(base.width(), base.height()) / 8f).toInt())
        val scales = floatArrayOf(0.78f, 0.88f, 0.96f, 1.0f, 1.06f, 1.14f, 1.28f)
        for (scale in scales) {
            val sized = base.scaledAboutCenter(scale)
            var dy = -ry.toInt()
            while (dy <= ry.toInt()) {
                var dx = -rx.toInt()
                while (dx <= rx.toInt()) {
                    val b = centeredBox(sized.centerX() + dx, sized.centerY() + dy, sized.width(), sized.height())
                    if (inside(b, frame.width, frame.height)) {
                        val d = descriptor(frame, b)
                        if (d != null) {
                            val s = model.score(d)
                            if (best == null || s > best.score) best = Candidate(b, d, s)
                        }
                    }
                    dx += step
                }
                dy += step
            }
        }
        return best
    }

    private fun quality(score: Float) = ((score - 0.30f) / 0.70f).coerceIn(0f, 1f)

    private data class Candidate(val box: BoxF, val desc: FloatArray, val score: Float)

    private class QualityGateCore {
        private var lostStreak = 0
        fun reset() { lostStreak = 0 }

        fun classify(score: Float): CoreTrackState {
            return when {
                score >= 0.64f -> {
                    lostStreak = 0
                    CoreTrackState.TRACKING
                }
                score >= 0.47f -> {
                    lostStreak = 0
                    CoreTrackState.UNCERTAIN
                }
                else -> {
                    if (score < 0.40f) lostStreak++ else lostStreak = max(0, lostStreak - 1)
                    if (lostStreak >= 2) CoreTrackState.LOST else CoreTrackState.UNCERTAIN
                }
            }
        }
    }

    private class ReacquireCore {
        private var pending: BoxF? = null
        private var confirm = 0
        private var searchFrame = 0

        fun reset() {
            pending = null
            confirm = 0
            searchFrame = 0
        }

        fun search(frame: GrayFrame, predicted: BoxF, trusted: BoxF, model: TargetModelCore): ReacquireResult {
            searchFrame++
            var best = when {
                searchFrame <= 2 -> scanRegion(frame, predicted, model, 1.8f)
                searchFrame <= 5 -> scanRegion(frame, predicted, model, 4.0f)
                else -> scanFull(frame, trusted, model)
            }
            if (best != null) best = refine(frame, best, model)

            if (best == null || best.score < 0.68f) {
                pending = null
                confirm = 0
                return ReacquireResult(false, best?.box, best?.score ?: -1f)
            }

            val p = pending
            if (p != null && centerDistance(p, best.box) <= max(14f, best.box.width() * 0.85f)) {
                confirm++
            } else {
                confirm = 1
            }
            pending = best.box

            return if (confirm >= 3) {
                pending = null
                confirm = 0
                searchFrame = 0
                ReacquireResult(true, best.box, best.score)
            } else {
                ReacquireResult(false, best.box, best.score)
            }
        }

        private fun scanRegion(frame: GrayFrame, base: BoxF, model: TargetModelCore, multiplier: Float): Candidate? {
            var best: Candidate? = null
            val rx = max(30f, base.width() * multiplier)
            val ry = max(24f, base.height() * multiplier)
            val scales = floatArrayOf(0.72f, 0.84f, 0.94f, 1.0f, 1.08f, 1.20f, 1.36f)
            for (scale in scales) {
                val w = base.width() * scale
                val h = base.height() * scale
                val step = max(4, (min(w, h) * 0.30f).toInt())
                var dy = -ry.toInt()
                while (dy <= ry.toInt()) {
                    var dx = -rx.toInt()
                    while (dx <= rx.toInt()) {
                        val b = centeredBox(base.centerX() + dx, base.centerY() + dy, w, h)
                        if (inside(b, frame.width, frame.height)) {
                            val d = descriptor(frame, b)
                            if (d != null) {
                                val s = model.score(d)
                                if (best == null || s > best.score) best = Candidate(b, d, s)
                            }
                        }
                        dx += step
                    }
                    dy += step
                }
            }
            return best
        }

        private fun scanFull(frame: GrayFrame, base: BoxF, model: TargetModelCore): Candidate? {
            var best: Candidate? = null
            val scales = floatArrayOf(0.68f, 0.80f, 0.92f, 1.0f, 1.12f, 1.28f, 1.48f)
            for (scale in scales) {
                val w = (base.width() * scale).coerceIn(8f, frame.width * 0.48f)
                val h = (base.height() * scale).coerceIn(6f, frame.height * 0.48f)
                val sx = max(5, (w * 0.28f).toInt())
                val sy = max(4, (h * 0.28f).toInt())
                var cy = h * 0.5f + 1f
                while (cy < frame.height - h * 0.5f - 1f) {
                    var cx = w * 0.5f + 1f
                    while (cx < frame.width - w * 0.5f - 1f) {
                        val b = centeredBox(cx, cy, w, h)
                        val d = descriptor(frame, b)
                        if (d != null) {
                            val s = model.score(d)
                            if (best == null || s > best.score) best = Candidate(b, d, s)
                        }
                        cx += sx
                    }
                    cy += sy
                }
            }
            return best
        }

        private fun refine(frame: GrayFrame, seed: Candidate, model: TargetModelCore): Candidate {
            var best = seed
            val base = seed.box
            val step = max(1, (min(base.width(), base.height()) / 10f).toInt())
            for (scale in floatArrayOf(0.90f, 0.96f, 1.0f, 1.05f, 1.12f)) {
                var dy = -step * 3
                while (dy <= step * 3) {
                    var dx = -step * 3
                    while (dx <= step * 3) {
                        val b = centeredBox(
                            base.centerX() + dx,
                            base.centerY() + dy,
                            base.width() * scale,
                            base.height() * scale
                        )
                        if (inside(b, frame.width, frame.height)) {
                            val d = descriptor(frame, b)
                            if (d != null) {
                                val s = model.score(d)
                                if (s > best.score) best = Candidate(b, d, s)
                            }
                        }
                        dx += step
                    }
                    dy += step
                }
            }
            return best
        }

        data class ReacquireResult(
            val confirmed: Boolean,
            val box: BoxF?,
            val score: Float
        )
    }
}

private class TargetModelCore {
    private var anchor = FloatArray(0)
    private var stable = FloatArray(0)
    private var adaptive = FloatArray(0)
    private var strong = 0

    var updates = 0
        private set
    var restores = 0
        private set
    var policy = "RESET"
        private set

    fun reset() {
        anchor = FloatArray(0)
        stable = FloatArray(0)
        adaptive = FloatArray(0)
        updates = 0
        restores = 0
        strong = 0
        policy = "RESET"
    }

    fun init(desc: FloatArray) {
        anchor = desc.copyOf()
        stable = desc.copyOf()
        adaptive = desc.copyOf()
        policy = "HOLD"
    }

    fun score(desc: FloatArray): Float {
        if (adaptive.isEmpty()) return -1f
        return maxOf(appearanceScore(anchor, desc), appearanceScore(stable, desc), appearanceScore(adaptive, desc))
    }

    fun update(desc: FloatArray, score: Float) {
        if (adaptive.isEmpty() || score < 0.72f) {
            policy = "HOLD"
            return
        }
        val alpha = if (score > 0.88f) 0.05f else 0.025f
        for (i in adaptive.indices) adaptive[i] = (1f - alpha) * adaptive[i] + alpha * desc[i]
        updates++
        policy = "UPDATE"
        if (score > 0.90f) {
            strong++
            if (strong % 12 == 0) {
                for (i in stable.indices) stable[i] = 0.985f * stable[i] + 0.015f * desc[i]
            }
        }
    }

    fun restore() {
        if (stable.isNotEmpty()) {
            adaptive = stable.copyOf()
            restores++
            policy = "RESTORE_STABLE"
        }
    }
}

private fun descriptor(frame: GrayFrame, b: BoxF): FloatArray? {
    if (!inside(b, frame.width, frame.height)) return null
    val cols = 11
    val rows = 9
    val out = FloatArray(cols * rows)
    var k = 0
    for (j in 0 until rows) {
        for (i in 0 until cols) {
            val x = (b.left + (i + 0.5f) * b.width() / cols).toInt()
            val y = (b.top + (j + 0.5f) * b.height() / rows).toInt()
            if (x < 1 || y < 1 || x >= frame.width - 1 || y >= frame.height - 1) return null
            out[k++] = frame.gray(x, y)
        }
    }
    return out
}

private fun appearanceScore(a: FloatArray, b: FloatArray): Float {
    if (a.size != b.size || a.isEmpty()) return -1f
    val structural = ncc(a, b)
    var mad = 0f
    for (i in a.indices) mad += abs(a[i] - b[i])
    mad /= a.size
    val absolute = (1f - mad / 0.35f).coerceIn(-1f, 1f)
    return 0.72f * structural + 0.28f * absolute
}

private fun ncc(a: FloatArray, b: FloatArray): Float {
    if (a.size != b.size || a.isEmpty()) return -1f
    var ma = 0f
    var mb = 0f
    for (i in a.indices) {
        ma += a[i]
        mb += b[i]
    }
    ma /= a.size
    mb /= b.size
    var num = 0f
    var aa = 0f
    var bb = 0f
    for (i in a.indices) {
        val x = a[i] - ma
        val y = b[i] - mb
        num += x * y
        aa += x * x
        bb += y * y
    }
    val den = sqrt(aa * bb)
    return if (den > 1e-7f) num / den else -1f
}

private fun centeredBox(cx: Float, cy: Float, w: Float, h: Float) =
    BoxF(cx - w * 0.5f, cy - h * 0.5f, cx + w * 0.5f, cy + h * 0.5f)

private fun inside(b: BoxF, w: Int, h: Int) =
    b.left >= 1f && b.top >= 1f && b.right < w - 1f && b.bottom < h - 1f && b.width() >= 6f && b.height() >= 6f

private fun clamp(b: BoxF, w: Int, h: Int): BoxF {
    val bw = min(b.width(), w - 2f).coerceAtLeast(6f)
    val bh = min(b.height(), h - 2f).coerceAtLeast(6f)
    val cx = b.centerX().coerceIn(1f + bw * 0.5f, w - 1f - bw * 0.5f)
    val cy = b.centerY().coerceIn(1f + bh * 0.5f, h - 1f - bh * 0.5f)
    return centeredBox(cx, cy, bw, bh)
}

private fun centerDistance(a: BoxF, b: BoxF) = hypot(a.centerX() - b.centerX(), a.centerY() - b.centerY())
