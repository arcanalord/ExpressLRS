package club.fpv.real0.core

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
    private var lastKnown: BoxF? = null
    private var predicted: BoxF? = null
    private var vx = 0f
    private var vy = 0f
    private var state = CoreTrackState.IDLE

    val policy: String get() = model.policy
    val modelUpdates: Int get() = model.updates
    val modelRestores: Int get() = model.restores

    fun reset() {
        model.reset()
        gate.reset()
        reacquire.reset()
        measured = null
        lastKnown = null
        predicted = null
        vx = 0f
        vy = 0f
        state = CoreTrackState.IDLE
    }

    fun init(frame: GrayFrame, initial: BoxF) {
        reset()
        val b = clamp(initial, frame.width, frame.height)
        val d = descriptor(frame, b) ?: return
        model.init(d)
        measured = b
        lastKnown = b
        predicted = b
        state = CoreTrackState.TRACKING
    }

    fun update(frame: GrayFrame): CoreTrackerResult {
        val t0 = System.nanoTime()
        val current = measured
        if (current != null) {
            val searchBase = predicted ?: current
            val best = scanLocal(frame, searchBase)
            val score = best?.score ?: -1f
            val next = gate.classify(score)
            val quality = quality(score)

            if (best == null || next == CoreTrackState.LOST) {
                lastKnown = current
                measured = null
                state = CoreTrackState.LOST
                model.restore()
                predicted = clamp((predicted ?: current).translated(vx, vy), frame.width, frame.height)
                vx *= 0.90f
                vy *= 0.90f
                return result(quality, t0, "local lost")
            }

            val prev = current
            measured = best.box
            lastKnown = best.box
            vx = 0.62f * vx + 0.38f * (best.box.centerX() - prev.centerX())
            vy = 0.62f * vy + 0.38f * (best.box.centerY() - prev.centerY())
            predicted = clamp(best.box.translated(vx, vy), frame.width, frame.height)
            state = next
            if (next == CoreTrackState.TRACKING && score >= 0.72f) model.update(best.desc, score)
            return result(quality, t0, "local multi-scale")
        }

        val base = predicted ?: lastKnown
        if (base == null) return CoreTrackerResult(CoreTrackState.IDLE, null, null, 0f, 0f, "not initialized")

        predicted = clamp(base.translated(vx, vy), frame.width, frame.height)
        vx *= 0.90f
        vy *= 0.90f
        val reacq = reacquire.search(frame, predicted ?: base, model)
        val q = quality(reacq.score)
        if (reacq.confirmed && reacq.box != null && reacq.desc != null) {
            measured = reacq.box
            lastKnown = reacq.box
            predicted = reacq.box
            vx = 0f
            vy = 0f
            gate.reset()
            state = CoreTrackState.REACQUIRED
            model.update(reacq.desc, reacq.score)
            return result(q, t0, "full-frame reacquired")
        }
        state = CoreTrackState.SEARCHING
        return result(q, t0, "full-frame searching")
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
        val rx = max(24f, base.width() * 1.15f)
        val ry = max(18f, base.height() * 1.15f)
        val step = max(3, (min(base.width(), base.height()) / 7f).toInt())
        val scales = floatArrayOf(0.82f, 0.91f, 1.0f, 1.10f, 1.22f)
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
                            if (best == null || s > best!!.score) best = Candidate(b, d, s)
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

        fun reset() {
            pending = null
            confirm = 0
        }

        fun search(frame: GrayFrame, base: BoxF, model: TargetModelCore): ReacquireResult {
            var bestBox: BoxF? = null
            var bestDesc: FloatArray? = null
            var bestScore = -1f
            val scales = floatArrayOf(0.78f, 0.90f, 1.0f, 1.12f, 1.28f)
            for (scale in scales) {
                val w = (base.width() * scale).coerceIn(10f, frame.width * 0.45f)
                val h = (base.height() * scale).coerceIn(8f, frame.height * 0.45f)
                val sx = max(7, (w * 0.34f).toInt())
                val sy = max(6, (h * 0.34f).toInt())
                var cy = h * 0.5f + 1f
                while (cy < frame.height - h * 0.5f - 1f) {
                    var cx = w * 0.5f + 1f
                    while (cx < frame.width - w * 0.5f - 1f) {
                        val b = centeredBox(cx, cy, w, h)
                        val d = descriptor(frame, b)
                        if (d != null) {
                            val s = model.score(d)
                            if (s > bestScore) {
                                bestScore = s
                                bestBox = b
                                bestDesc = d
                            }
                        }
                        cx += sx
                    }
                    cy += sy
                }
            }

            if (bestBox == null || bestDesc == null || bestScore < 0.70f) {
                pending = null
                confirm = 0
                return ReacquireResult(false, null, null, bestScore)
            }

            val p = pending
            if (p != null && centerDistance(p, bestBox) <= max(12f, bestBox.width() * 0.60f)) {
                confirm++
            } else {
                pending = bestBox
                confirm = 1
            }

            return if (confirm >= 2) {
                pending = null
                confirm = 0
                ReacquireResult(true, bestBox, bestDesc, bestScore)
            } else {
                ReacquireResult(false, bestBox, bestDesc, bestScore)
            }
        }

        data class ReacquireResult(
            val confirmed: Boolean,
            val box: BoxF?,
            val desc: FloatArray?,
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
    val out = FloatArray(35)
    var k = 0
    for (j in 0 until 5) {
        for (i in 0 until 7) {
            val x = (b.left + (i + 0.5f) * b.width() / 7f).toInt()
            val y = (b.top + (j + 0.5f) * b.height() / 5f).toInt()
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
    for (i in a.indices) mad += kotlin.math.abs(a[i] - b[i])
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
