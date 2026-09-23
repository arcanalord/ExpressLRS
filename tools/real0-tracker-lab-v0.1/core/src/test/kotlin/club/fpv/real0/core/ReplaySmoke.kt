package club.fpv.real0.core

import kotlin.math.abs

private class SyntheticFrame(
    override val width: Int,
    override val height: Int,
    private val target: BoxF
) : GrayFrame {
    override fun gray(x: Int, y: Int): Float {
        val bg = ((x * 13 + y * 7) % 31) / 310f
        if (x >= target.left && x < target.right && y >= target.top && y < target.bottom) {
            val tx = x - target.left.toInt()
            val ty = y - target.top.toInt()
            val checker = if (((tx / 3) + (ty / 3)) % 2 == 0) 0.90f else 0.25f
            return (checker + ((tx * 5 + ty * 3) % 17) / 100f).coerceAtMost(1f)
        }
        return bg
    }
}

fun main() {
    val tracker = NccTrackerCore()
    val initial = BoxF(40f, 48f, 62f, 68f)
    tracker.init(SyntheticFrame(160, 120, initial), initial)

    var last: CoreTrackerResult? = null
    for (i in 1..8) {
        val expected = initial.translated(i * 2f, i.toFloat())
        val result = tracker.update(SyntheticFrame(160, 120, expected))
        val measured = checkNotNull(result.measuredBox) { "frame $i: missing measurement: $result" }
        check(abs(measured.centerX() - expected.centerX()) <= 3.5f) {
            "frame $i: x drift ${measured.centerX()} vs ${expected.centerX()}"
        }
        check(abs(measured.centerY() - expected.centerY()) <= 3.5f) {
            "frame $i: y drift ${measured.centerY()} vs ${expected.centerY()}"
        }
        check(result.state != CoreTrackState.LOST) { "frame $i unexpectedly LOST" }
        last = result
    }

    check(last?.state == CoreTrackState.TRACKING) { "expected TRACKING, got ${last?.state}" }
    val updates = tracker.modelUpdates
    check(updates > 0) { "expected adaptive model update" }

    tracker.reset()
    val idle = tracker.update(SyntheticFrame(160, 120, initial))
    check(idle.state == CoreTrackState.IDLE) { "reset must return IDLE" }

    println("CORE_PASS synthetic replay: state=${last?.state}, q=${last?.quality}, updates=$updates")
}
