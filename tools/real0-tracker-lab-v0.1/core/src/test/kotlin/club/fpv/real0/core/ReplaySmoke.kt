package club.fpv.real0.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private data class Target(val box: BoxF, val visible: Boolean = true)

private class SyntheticFrame(
    override val width: Int,
    override val height: Int,
    private val target: Target?,
    private val distractor: Target? = null,
    override val timestampNs: Long = 0L
) : GrayFrame {
    override fun gray(x: Int, y: Int): Float {
        val bg = ((x * 11 + y * 7 + (x * y) % 17) % 47) / 470f
        val t = target
        if (t != null && t.visible && insideTarget(t.box, x, y)) return targetPattern(t.box, x, y)
        val d = distractor
        if (d != null && d.visible && insideTarget(d.box, x, y)) return distractorPattern(d.box, x, y)
        return bg
    }

    private fun targetPattern(b: BoxF, x: Int, y: Int): Float {
        val u = ((x - b.left) / b.width()).coerceIn(0f, 1f)
        val v = ((y - b.top) / b.height()).coerceIn(0f, 1f)
        val markA = if (u > 0.12f && u < 0.36f && v > 0.10f && v < 0.42f) 0.56f else 0f
        val markB = if (u > 0.58f && u < 0.88f && v > 0.55f && v < 0.82f) 0.34f else 0f
        val diagonal = if (kotlin.math.abs(v - (0.20f + 0.55f * u)) < 0.09f) 0.28f else 0f
        return (0.10f + 0.18f * u + 0.11f * v + markA + markB + diagonal).coerceIn(0f, 1f)
    }

    private fun distractorPattern(b: BoxF, x: Int, y: Int): Float {
        val u = ((x - b.left) / b.width()).coerceIn(0f, 1f)
        val v = ((y - b.top) / b.height()).coerceIn(0f, 1f)
        return (0.22f + 0.42f * u + 0.08f * v +
            if (kotlin.math.abs(v - (0.72f - 0.30f * u)) < 0.07f) 0.12f else 0f).coerceIn(0f, 1f)
    }

    private fun insideTarget(b: BoxF, x: Int, y: Int) =
        x >= b.left && x < b.right && y >= b.top && y < b.bottom
}

private fun box(cx: Float, cy: Float, w: Float, h: Float) =
    BoxF(cx - w / 2f, cy - h / 2f, cx + w / 2f, cy + h / 2f)

private fun assertNear(actual: BoxF?, expected: BoxF, tolerance: Float, label: String) {
    val a = checkNotNull(actual) { "$label: missing measurement" }
    check(abs(a.centerX() - expected.centerX()) <= tolerance) { "$label x ${a.centerX()} vs ${expected.centerX()}" }
    check(abs(a.centerY() - expected.centerY()) <= tolerance) { "$label y ${a.centerY()} vs ${expected.centerY()}" }
}

private fun iou(a: BoxF, b: BoxF): Float {
    val left = max(a.left, b.left)
    val top = max(a.top, b.top)
    val right = min(a.right, b.right)
    val bottom = min(a.bottom, b.bottom)
    val intersection = max(0f, right - left) * max(0f, bottom - top)
    val areaA = a.width() * a.height()
    val areaB = b.width() * b.height()
    return intersection / (areaA + areaB - intersection).coerceAtLeast(1e-6f)
}

fun main() {
    val tracker = NccTrackerCore()

    var target = box(44f, 46f, 24f, 20f)
    tracker.init(SyntheticFrame(200, 140, Target(target)), target)
    for (i in 1..7) {
        target = box(44f + i * 8f, 46f + i * 3f, 24f, 20f)
        val r = tracker.update(SyntheticFrame(200, 140, Target(target)))
        check(r.state != CoreTrackState.LOST && r.state != CoreTrackState.SEARCHING) { "translation frame $i lost: $r" }
        assertNear(r.measuredBox, target, 6f, "translation $i")
    }

    tracker.reset()
    target = box(70f, 60f, 24f, 18f)
    tracker.init(SyntheticFrame(220, 160, Target(target)), target)
    for (i in 1..7) {
        val s = 1f + i * 0.08f
        target = box(70f + i * 4f, 60f + i * 2f, 24f * s, 18f * s)
        val r = tracker.update(SyntheticFrame(220, 160, Target(target)))
        check(r.state != CoreTrackState.LOST && r.state != CoreTrackState.SEARCHING) { "scale frame $i lost: $r" }
        assertNear(r.measuredBox, target, 7f, "scale $i")
    }

    tracker.reset()
    var ts = 1_000_000_000L
    target = box(44f, 46f, 24f, 20f)
    tracker.init(SyntheticFrame(240, 170, Target(target), timestampNs = ts), target)
    val intervalsMs = listOf(33L, 33L, 33L, 120L, 33L, 33L, 180L, 33L)
    for ((i, ms) in intervalsMs.withIndex()) {
        ts += ms * 1_000_000L
        val seconds = ms / 1000f
        target = box(
            target.centerX() + 135f * seconds,
            target.centerY() + 55f * seconds,
            24f * (1f + i * 0.018f),
            20f * (1f + i * 0.018f)
        )
        val r = tracker.update(SyntheticFrame(240, 170, Target(target), timestampNs = ts))
        check(r.state != CoreTrackState.LOST && r.state != CoreTrackState.SEARCHING) { "frame-gap tracking lost at $i: $r" }
    }

    repeat(4) {
        ts += 33_000_000L
        tracker.update(SyntheticFrame(240, 170, null, timestampNs = ts))
    }

    val reappear = box(176f, 112f, 28f, 22f)
    var reacquireFrame = -1
    var updatesBeforeReacquired = -1
    var updatesAtReacquired = -1
    repeat(8) { i ->
        ts += 33_000_000L
        val moved = box(
            reappear.centerX() + i * 3.2f,
            reappear.centerY() + i * 1.1f,
            reappear.width(),
            reappear.height()
        )
        val beforeUpdate = tracker.modelUpdates
        val r = tracker.update(
            SyntheticFrame(
                240,
                170,
                Target(moved),
                Target(box(92f, 102f, 30f, 24f)),
                timestampNs = ts
            )
        )
        if (r.state == CoreTrackState.REACQUIRED && reacquireFrame < 0) {
            reacquireFrame = i + 1
            updatesBeforeReacquired = beforeUpdate
            updatesAtReacquired = tracker.modelUpdates
        }
    }
    check(reacquireFrame in 1..6) { "staged reacquire failed/too late: $reacquireFrame" }
    check(updatesAtReacquired == updatesBeforeReacquired) { "model changed on REACQUIRED frame" }

    val negative = NccTrackerCore()
    ts = 2_000_000_000L
    val initial = box(60f, 55f, 26f, 20f)
    negative.init(SyntheticFrame(220, 150, Target(initial), timestampNs = ts), initial)
    repeat(3) {
        ts += 33_000_000L
        negative.update(SyntheticFrame(220, 150, null, timestampNs = ts))
    }
    var falseReacquire = false
    repeat(8) {
        ts += 33_000_000L
        val r = negative.update(
            SyntheticFrame(
                220,
                150,
                null,
                Target(box(150f, 100f, 28f, 22f)),
                timestampNs = ts
            )
        )
        if (r.state == CoreTrackState.REACQUIRED) falseReacquire = true
    }
    check(!falseReacquire) { "false reacquire on distractor" }

    val autoFit = AutoFitCore()
    val cases = listOf(
        Triple("small", box(82f, 66f, 12f, 8f), 82f to 66f),
        Triple("large", box(96f, 70f, 58f, 42f), 88f to 64f),
        Triple("offset", box(120f, 78f, 34f, 24f), 111f to 72f)
    )
    for ((name, expected, seed) in cases) {
        val fitted = autoFit.fit(SyntheticFrame(220, 150, Target(expected)), seed.first, seed.second)
        val b = checkNotNull(fitted.box) { "$name AutoFit missing" }
        val overlap = iou(b, expected)
        check(overlap >= 0.30f) { "$name AutoFit overlap too low: $overlap $b" }
        println("AUTOFIT $name confidence=${fitted.confidence} iou=$overlap box=$b")
    }

    val stabilizer = LockStabilizerCore(requiredFrames = 3)
    var confirmed = false
    repeat(4) { i ->
        val b = box(80f + i * 1.2f, 64f + i * 0.7f, 28f, 20f)
        val fit = autoFit.fit(SyntheticFrame(220, 150, Target(b)), b.centerX(), b.centerY())
        if (stabilizer.update(fit).first) confirmed = true
    }
    check(confirmed) { "LockStabilizer failed to confirm" }

    tracker.reset()
    val idle = tracker.update(SyntheticFrame(160, 120, null))
    check(idle.state == CoreTrackState.IDLE) { "reset must return IDLE" }

    println("CORE_PASS v0.1.6 candidate: autofit + stabilization + timestamp motion + staged reacquire + distractor rejection")
}
