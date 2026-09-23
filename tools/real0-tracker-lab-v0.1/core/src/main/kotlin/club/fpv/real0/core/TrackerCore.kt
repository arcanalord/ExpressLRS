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
    private var tpl = FloatArray(0)
    private var tw = 0
    private var th = 0
    private var box: BoxF? = null
    private var prev: BoxF? = null
    private var predicted: BoxF? = null
    private var vx = 0f
    private var vy = 0f
    private var bad = 0
    private var good = 0
    private val model = TargetModelCore()

    val policy: String get() = model.policy
    val modelUpdates: Int get() = model.updates
    val modelRestores: Int get() = model.restores

    fun reset() {
        tpl = FloatArray(0)
        box = null
        prev = null
        predicted = null
        vx = 0f
        vy = 0f
        bad = 0
        good = 0
        model.reset()
    }

    fun init(frame: GrayFrame, initial: BoxF) {
        reset()
        val b = clamp(initial, frame.width, frame.height)
        box = b
        prev = b
        predicted = b
        tw = min(48, max(16, b.width().toInt()))
        th = min(48, max(16, b.height().toInt()))
        tpl = sample(frame, b, tw, th)
        normalize(tpl)
        model.init(frame, b, tw, th)
    }

    fun update(frame: GrayFrame): CoreTrackerResult {
        val t0 = System.nanoTime()
        val base = box ?: return CoreTrackerResult(CoreTrackState.IDLE, null, null, 0f, 0f, "not initialized")
        val rx = max(12f, base.width() * 0.75f)
        val ry = max(10f, base.height() * 0.75f)
        val step = max(2, min(base.width(), base.height()).toInt() / 18)
        var best = -2f
        var bestBox = base
        var dy = (-ry).toInt()
        while (dy <= ry.toInt()) {
            var dx = (-rx).toInt()
            while (dx <= rx.toInt()) {
                val c = clamp(base.translated(dx.toFloat(), dy.toFloat()), frame.width, frame.height)
                if (c.width() >= 8 && c.height() >= 8) {
                    val s = sample(frame, c, tw, th)
                    normalize(s)
                    val q = .55f * ((dot(tpl, s) + 1f) * .5f) + .45f * model.score(frame, c)
                    if (q > best) {
                        best = q
                        bestBox = c
                    }
                }
                dx += step
            }
            dy += step
        }

        var q = best.coerceIn(0f, 1f)
        val j = jump(base, bestBox)
        if (j > 1.3f) q = (q - .22f).coerceAtLeast(0f)
        val state = when {
            q >= .62f -> {
                good++
                bad = 0
                if (good >= 2) CoreTrackState.TRACKING else CoreTrackState.UNCERTAIN
            }
            q >= .40f -> {
                good = 0
                bad = 0
                CoreTrackState.UNCERTAIN
            }
            else -> {
                bad++
                good = 0
                if (bad >= 2) CoreTrackState.LOST else CoreTrackState.UNCERTAIN
            }
        }

        val measured = if (state == CoreTrackState.LOST) null else bestBox
        if (measured != null) {
            val p = prev
            if (p != null) {
                vx = .7f * vx + .3f * (measured.centerX() - p.centerX())
                vy = .7f * vy + .3f * (measured.centerY() - p.centerY())
            }
            prev = measured
            box = measured
            predicted = measured.translated(vx, vy)
            if (state == CoreTrackState.TRACKING && q >= .70f) {
                model.commit(frame, measured, q)
                val s = sample(frame, measured, tw, th)
                normalize(s)
                for (i in tpl.indices) tpl[i] = .975f * tpl[i] + .025f * s[i]
                normalize(tpl)
            }
        } else {
            model.restore()
            predicted = predicted?.translated(vx, vy)
        }

        return CoreTrackerResult(
            state,
            measured,
            predicted,
            q,
            (System.nanoTime() - t0) / 1e6f,
            "NCC-MS ${model.policy}"
        )
    }

    private fun jump(a: BoxF, b: BoxF) =
        hypot(a.centerX() - b.centerX(), a.centerY() - b.centerY()) /
            hypot(a.width(), a.height()).coerceAtLeast(1f)

    private fun dot(a: FloatArray, b: FloatArray): Float {
        var s = 0f
        for (i in a.indices) s += a[i] * b[i]
        return s
    }

    private fun normalize(a: FloatArray) {
        if (a.isEmpty()) return
        var m = 0f
        for (v in a) m += v
        m /= a.size
        var ss = 0f
        for (i in a.indices) {
            a[i] -= m
            ss += a[i] * a[i]
        }
        val d = sqrt(ss.coerceAtLeast(1e-9f))
        for (i in a.indices) a[i] /= d
    }

    private fun sample(frame: GrayFrame, r: BoxF, w: Int, h: Int): FloatArray {
        val out = FloatArray(w * h)
        for (y in 0 until h) {
            val py = (r.top + (y + .5f) * r.height() / h).toInt().coerceIn(0, frame.height - 1)
            for (x in 0 until w) {
                val px = (r.left + (x + .5f) * r.width() / w).toInt().coerceIn(0, frame.width - 1)
                out[y * w + x] = frame.gray(px, py).coerceIn(0f, 1f)
            }
        }
        return out
    }

    private fun clamp(r: BoxF, w: Int, h: Int) = BoxF(
        r.left.coerceIn(0f, w - 2f),
        r.top.coerceIn(0f, h - 2f),
        r.right.coerceIn(2f, w.toFloat()),
        r.bottom.coerceIn(2f, h.toFloat())
    )
}

private class TargetModelCore {
    private var anchor = FloatArray(0)
    private var stable = FloatArray(0)
    private var adaptive = FloatArray(0)
    private var sampleW = 0
    private var sampleH = 0
    var updates = 0
        private set
    var restores = 0
        private set
    var policy = "RESET"
        private set
    private val ready get() = adaptive.isNotEmpty()

    fun reset() {
        anchor = FloatArray(0)
        stable = FloatArray(0)
        adaptive = FloatArray(0)
        sampleW = 0
        sampleH = 0
        updates = 0
        restores = 0
        policy = "RESET"
    }

    fun init(frame: GrayFrame, box: BoxF, width: Int, height: Int) {
        sampleW = width
        sampleH = height
        val s = sample(frame, box)
        anchor = s.copyOf()
        stable = s.copyOf()
        adaptive = s.copyOf()
        policy = "HOLD"
    }

    fun score(frame: GrayFrame, box: BoxF): Float {
        if (!ready) return 0f
        val s = sample(frame, box)
        val raw = .25f * dot(anchor, s) + .25f * dot(stable, s) + .5f * dot(adaptive, s)
        return ((raw + 1f) * .5f).coerceIn(0f, 1f)
    }

    fun commit(frame: GrayFrame, box: BoxF, quality: Float) {
        if (!ready || quality < .70f) {
            policy = "HOLD"
            return
        }
        val s = sample(frame, box)
        for (i in adaptive.indices) adaptive[i] = .97f * adaptive[i] + .03f * s[i]
        normalize(adaptive)
        updates++
        policy = "UPDATE"
        if (updates % 30 == 0 && quality >= .76f) stable = adaptive.copyOf()
    }

    fun restore() {
        if (stable.isNotEmpty()) {
            adaptive = stable.copyOf()
            restores++
            policy = "RESTORE_STABLE"
        }
    }

    private fun sample(frame: GrayFrame, r: BoxF): FloatArray {
        val out = FloatArray(sampleW * sampleH)
        for (y in 0 until sampleH) {
            val py = (r.top + (y + .5f) * r.height() / sampleH).toInt().coerceIn(0, frame.height - 1)
            for (x in 0 until sampleW) {
                val px = (r.left + (x + .5f) * r.width() / sampleW).toInt().coerceIn(0, frame.width - 1)
                out[y * sampleW + x] = frame.gray(px, py).coerceIn(0f, 1f)
            }
        }
        normalize(out)
        return out
    }

    private fun dot(a: FloatArray, b: FloatArray): Float {
        var s = 0f
        for (i in a.indices) s += a[i] * b[i]
        return s
    }

    private fun normalize(a: FloatArray) {
        if (a.isEmpty()) return
        var m = 0f
        for (v in a) m += v
        m /= a.size
        var ss = 0f
        for (i in a.indices) {
            a[i] -= m
            ss += a[i] * a[i]
        }
        val d = sqrt(ss.coerceAtLeast(1e-9f))
        for (i in a.indices) a[i] /= d
    }
}
