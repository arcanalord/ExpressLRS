package ru.fpvclub.tracker.tracking

import java.util.ArrayDeque
import kotlin.math.exp
import kotlin.math.ln

/** Multi-frame temporal model robust to a single bad frame. */
class MotionModel(private val historySize: Int = 7) {
    private val history = ArrayDeque<Box>()

    fun reset(box: Box? = null) {
        history.clear()
        if (box != null) history.addLast(box)
    }

    fun update(box: Box) {
        history.addLast(box)
        while (history.size > historySize) history.removeFirst()
    }

    fun predict(framesAhead: Float = 1f): Box? {
        val last = history.lastOrNull() ?: return null
        if (history.size < 2) return last
        val boxes = history.toList()
        val dx = ArrayList<Float>(boxes.size - 1)
        val dy = ArrayList<Float>(boxes.size - 1)
        val dw = ArrayList<Float>(boxes.size - 1)
        val dh = ArrayList<Float>(boxes.size - 1)
        for (i in 1 until boxes.size) {
            val a = boxes[i - 1]
            val b = boxes[i]
            dx += b.cx - a.cx
            dy += b.cy - a.cy
            dw += ln((b.w / a.w).coerceIn(.25f, 4f))
            dh += ln((b.h / a.h).coerceIn(.25f, 4f))
        }
        val vx = robustVelocity(dx)
        val vy = robustVelocity(dy)
        val vw = robustVelocity(dw)
        val vh = robustVelocity(dh)
        val w = (last.w * exp(vw * framesAhead)).coerceAtLeast(12f)
        val h = (last.h * exp(vh * framesAhead)).coerceAtLeast(12f)
        val cx = last.cx + vx * framesAhead
        val cy = last.cy + vy * framesAhead
        return Box(cx - w * .5f, cy - h * .5f, w, h)
    }

    private fun robustVelocity(values: List<Float>): Float {
        if (values.isEmpty()) return 0f
        val sorted = values.sorted()
        val median = if (sorted.size % 2 == 1) sorted[sorted.size / 2]
        else (sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) * .5f
        return median * .65f + values.last() * .35f
    }
}
