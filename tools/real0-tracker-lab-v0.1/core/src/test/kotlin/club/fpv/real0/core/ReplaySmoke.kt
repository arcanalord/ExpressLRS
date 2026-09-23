package club.fpv.real0.core

import kotlin.math.abs

private data class Target(val box: BoxF, val visible: Boolean = true)

private class SyntheticFrame(
    override val width: Int,
    override val height: Int,
    private val target: Target?,
    private val distractor: Target? = null
) : GrayFrame {
    override fun gray(x: Int, y: Int): Float {
        val bg = ((x * 11 + y * 7 + (x * y) % 13) % 37) / 370f
        val t = target
        if (t != null && t.visible && inside(t.box, x, y)) return targetPattern(t.box, x, y)
        val d = distractor
        if (d != null && d.visible && inside(d.box, x, y)) return distractorPattern(d.box, x, y)
        return bg
    }

    private fun targetPattern(b: BoxF, x: Int, y: Int): Float {
        val u = ((x - b.left) / b.width()).coerceIn(0f, 1f)
        val v = ((y - b.top) / b.height()).coerceIn(0f, 1f)
        val checker = if ((((u * 8).toInt()) + ((v * 6).toInt())) % 2 == 0) 0.92f else 0.18f
        return (checker + 0.05f * u + 0.03f * v).coerceIn(0f, 1f)
    }

    private fun distractorPattern(b: BoxF, x: Int, y: Int): Float {
        val u = ((x - b.left) / b.width()).coerceIn(0f, 1f)
        val v = ((y - b.top) / b.height()).coerceIn(0f, 1f)
        return (0.25f + 0.45f * u + 0.10f * v).coerceIn(0f, 1f)
    }

    private fun inside(b: BoxF, x: Int, y: Int) = x >= b.left && x < b.right && y >= b.top && y < b.bottom
}

private fun box(cx: Float, cy: Float, w: Float, h: Float) =
    BoxF(cx - w / 2f, cy - h / 2f, cx + w / 2f, cy + h / 2f)

private fun assertNear(actual: BoxF?, expected: BoxF, tolerance: Float, label: String) {
    val a = checkNotNull(actual) { "$label: missing measurement" }
    check(abs(a.centerX() - expected.centerX()) <= tolerance) { "$label x \${a.centerX()} vs \${expected.centerX()}" }
    check(abs(a.centerY() - expected.centerY()) <= tolerance) { "$label y \${a.centerY()} vs \${expected.centerY()}" }
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
    target = box(48f, 52f, 26f, 20f)
    tracker.init(SyntheticFrame(240, 170, Target(target)), target)
    tracker.update(SyntheticFrame(240, 170, Target(box(55f, 55f, 26f, 20f))))
    var sawLost = false
    repeat(4) {
        val r = tracker.update(SyntheticFrame(240, 170, null))
        if (r.state == CoreTrackState.LOST || r.state == CoreTrackState.SEARCHING) sawLost = true
    }
    check(sawLost) { "occlusion did not produce LOST/SEARCHING" }

    val reappear = box(174f, 112f, 28f, 22f)
    var reacquired = false
    repeat(4) {
        val r = tracker.update(SyntheticFrame(240, 170, Target(reappear), Target(box(90f, 100f, 30f, 24f))))
        if (r.state == CoreTrackState.REACQUIRED || r.state == CoreTrackState.TRACKING) {
            reacquired = true
            assertNear(r.measuredBox, reappear, 16f, "reacquire")
        }
    }
    check(reacquired) { "full-frame reacquire failed" }

    tracker.reset()
    val idle = tracker.update(SyntheticFrame(160, 120, null))
    check(idle.state == CoreTrackState.IDLE) { "reset must return IDLE" }

    println("CORE_PASS real-motion replay: translation + scale + occlusion + full-frame reacquire")
}
