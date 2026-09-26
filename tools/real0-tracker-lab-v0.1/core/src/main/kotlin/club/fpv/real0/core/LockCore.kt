package club.fpv.real0.core

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class AutoFitResult(val box: BoxF?, val confidence: Float, val reason: String)

class AutoFitCore {
    fun fit(frame: GrayFrame, seedX: Float, seedY: Float): AutoFitResult {
        var best: BoxF? = null
        var bestScore = -1e9f
        val scored = mutableListOf<Pair<BoxF, Float>>()
        val maxDim = min(frame.width, frame.height).toFloat()
        val widths = floatArrayOf(8f, 12f, 16f, 22f, 30f, 42f, 58f, 76f, 96f)
            .filter { it <= maxDim * 0.70f }
        val aspects = floatArrayOf(0.60f, 0.80f, 1.0f, 1.25f, 1.60f)
        val offsets = floatArrayOf(-0.22f, 0f, 0.22f)

        for (w in widths) {
            for (aspect in aspects) {
                val h = (w / aspect).coerceIn(6f, frame.height * 0.70f)
                for (ox in offsets) {
                    for (oy in offsets) {
                        val b = centered(seedX + ox * w, seedY + oy * h, w, h)
                        if (!insideLocal(b, frame.width, frame.height)) continue
                        val score = distinctiveness(frame, b)
                        scored += b to score
                        if (score > bestScore) {
                            bestScore = score
                            best = b
                        }
                    }
                }
            }
        }

        if (best == null) return AutoFitResult(null, 0f, "no candidate")

        val floorScore = max(0.02f, bestScore * 0.62f)
        val expanded = scored.filter { it.second >= floorScore }
            .maxByOrNull { it.first.width() * it.first.height() }
        if (expanded != null) best = expanded.first

        val chosenScore = scored.firstOrNull { it.first == best }?.second ?: bestScore
        val confidence = ((chosenScore - 0.03f) / 0.30f).coerceIn(0f, 1f)
        return AutoFitResult(
            best,
            confidence,
            if (confidence >= 0.30f) "rough boundary extent" else "weak rough extent"
        )
    }

    private fun distinctiveness(frame: GrayFrame, b: BoxF): Float {
        val inner = stats(frame, b) ?: return -1e9f
        val outer = scale(b, 1.45f, 1.45f)
        if (!insideLocal(outer, frame.width, frame.height)) return -1e9f
        val ring = ringStats(frame, b, outer) ?: return -1e9f

        val meanSeparation = abs(inner.first - ring.first)
        val varianceBonus = sqrt(inner.second.coerceAtLeast(0f)) * 0.12f
        val ringPenalty = sqrt(ring.second.coerceAtLeast(0f)) * 0.05f
        val boundary = boundaryContrast(frame, b)
        val hugePenalty = (b.width() * b.height()) / (frame.width * frame.height).toFloat() * 0.10f
        return 0.52f * meanSeparation + 0.38f * boundary + varianceBonus - ringPenalty - hugePenalty
    }

    private fun boundaryContrast(frame: GrayFrame, b: BoxF): Float {
        val d = max(2f, min(b.width(), b.height()) * 0.08f)
        val sx = ((b.width() - 2f * d) / b.width()).coerceAtLeast(0.55f)
        val sy = ((b.height() - 2f * d) / b.height()).coerceAtLeast(0.55f)
        val inner = scale(b, sx, sy)
        val outer = scale(b, 1f + 2f * d / b.width(), 1f + 2f * d / b.height())
        if (!insideLocal(outer, frame.width, frame.height)) return 0f
        val insideMean = stats(frame, inner)?.first ?: return 0f
        val outsideMean = ringStats(frame, b, outer)?.first ?: return 0f
        return abs(insideMean - outsideMean)
    }

    private fun stats(frame: GrayFrame, b: BoxF): Pair<Float, Float>? {
        var sum = 0f
        var sum2 = 0f
        var count = 0
        val stepX = max(1, (b.width() / 12f).toInt())
        val stepY = max(1, (b.height() / 10f).toInt())
        var y = ceil(b.top).toInt()

        while (y < floor(b.bottom).toInt()) {
            var x = ceil(b.left).toInt()
            while (x < floor(b.right).toInt()) {
                val v = frame.gray(x, y)
                sum += v
                sum2 += v * v
                count++
                x += stepX
            }
            y += stepY
        }

        if (count < 4) return null
        val mean = sum / count
        return mean to (sum2 / count - mean * mean).coerceAtLeast(0f)
    }

    private fun ringStats(frame: GrayFrame, inner: BoxF, outer: BoxF): Pair<Float, Float>? {
        var sum = 0f
        var sum2 = 0f
        var count = 0
        val stepX = max(1, (outer.width() / 16f).toInt())
        val stepY = max(1, (outer.height() / 14f).toInt())
        var y = ceil(outer.top).toInt()

        while (y < floor(outer.bottom).toInt()) {
            var x = ceil(outer.left).toInt()
            while (x < floor(outer.right).toInt()) {
                if (x < inner.left || x >= inner.right || y < inner.top || y >= inner.bottom) {
                    val v = frame.gray(x, y)
                    sum += v
                    sum2 += v * v
                    count++
                }
                x += stepX
            }
            y += stepY
        }

        if (count < 4) return null
        val mean = sum / count
        return mean to (sum2 / count - mean * mean).coerceAtLeast(0f)
    }

    private fun centered(cx: Float, cy: Float, w: Float, h: Float) =
        BoxF(cx - w * 0.5f, cy - h * 0.5f, cx + w * 0.5f, cy + h * 0.5f)

    private fun insideLocal(b: BoxF, w: Int, h: Int) =
        b.left >= 1f && b.top >= 1f && b.right < w - 1f && b.bottom < h - 1f &&
            b.width() >= 5f && b.height() >= 5f

    private fun scale(b: BoxF, sx: Float, sy: Float): BoxF {
        val hw = b.width() * sx * 0.5f
        val hh = b.height() * sy * 0.5f
        return BoxF(b.centerX() - hw, b.centerY() - hh, b.centerX() + hw, b.centerY() + hh)
    }
}

class LockStabilizerCore(private val requiredFrames: Int = 3) {
    private val boxes = ArrayDeque<BoxF>()

    fun reset() = boxes.clear()

    fun update(result: AutoFitResult): Pair<Boolean, BoxF?> {
        val box = result.box ?: run {
            boxes.clear()
            return false to null
        }
        if (result.confidence < 0.25f) {
            boxes.clear()
            return false to null
        }

        val prev = boxes.peekLast()
        if (prev != null) {
            val distance = hypot(
                (box.centerX() - prev.centerX()).toDouble(),
                (box.centerY() - prev.centerY()).toDouble()
            ).toFloat()
            val limit = max(5f, 0.35f * min(prev.width(), prev.height()))
            val widthRatio = box.width() / prev.width()
            val heightRatio = box.height() / prev.height()
            if (distance > limit || widthRatio !in 0.65f..1.55f || heightRatio !in 0.65f..1.55f) {
                boxes.clear()
            }
        }

        boxes.addLast(box)
        while (boxes.size > requiredFrames) boxes.removeFirst()
        if (boxes.size < requiredFrames) return false to box

        val list = boxes.toList()
        val averaged = BoxF(
            list.map { it.left }.average().toFloat(),
            list.map { it.top }.average().toFloat(),
            list.map { it.right }.average().toFloat(),
            list.map { it.bottom }.average().toFloat()
        )
        return true to averaged
    }
}
