package com.pointtrack.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Pure image-based global camera-motion estimator.
 *
 * It starts from local block matches between the previous and current grayscale
 * frames. A robust translation model is always available. When enough spatially
 * distributed matches support it, a small similarity residual (rotation +
 * uniform scale + translation) is fitted and used instead. No inertial sensor is
 * read or required.
 */
class GlobalImageMotionStabilizer(private val config: MotionConfig = MotionConfig()) {
    private data class Shift(
        val x: Double,
        val y: Double,
        val dx: Double,
        val dy: Double,
        val error: Double,
    )

    private data class SimilarityFit(
        val transform: FrameTransform2D,
        val rotationDeg: Double,
        val scale: Double,
        val residualPx: Double,
        val inlierCount: Int,
    )

    private var previous = ByteArray(0)
    private var width = 0
    private var height = 0
    private var referenceToCurrent = FrameTransform2D()

    fun reset() {
        previous = ByteArray(0)
        width = 0
        height = 0
        referenceToCurrent = FrameTransform2D()
    }

    fun update(frame: GrayFrame, estimateMotion: Boolean = true): MotionHint {
        if (!config.enabled) {
            seed(frame)
            return MotionHint()
        }
        if (frame.width != width || frame.height != height || previous.size != frame.width * frame.height) {
            width = frame.width
            height = frame.height
            previous = ByteArray(width * height)
            copyFrame(frame)
            referenceToCurrent = FrameTransform2D()
            return MotionHint()
        }
        if (!estimateMotion) {
            copyFrame(frame)
            return MotionHint(currentToStabilized = inverseAffine(referenceToCurrent))
        }

        val shifts = ArrayList<Shift>()
        val patchR = config.patchRadiusPx.coerceAtLeast(2)
        val searchR = config.searchRadiusPx.coerceAtLeast(2)
        val margin = searchR + patchR + 2
        if (width > 2 * margin + 4 && height > 2 * margin + 4) {
            val cols = config.gridColumns.coerceAtLeast(2)
            val rows = config.gridRows.coerceAtLeast(2)
            for (gy in 0 until rows) for (gx in 0 until cols) {
                val cx = margin + ((width - 2 * margin - 1) * (gx + 0.5) / cols).roundToInt()
                val cy = margin + ((height - 2 * margin - 1) * (gy + 0.5) / rows).roundToInt()
                if (patchRange(cx, cy, patchR) < config.minPatchRange) continue
                val best = bestShift(frame, cx, cy, patchR, searchR)
                if (best != null) {
                    shifts += Shift(
                        x = cx.toDouble(),
                        y = cy.toDouble(),
                        dx = best.first.toDouble(),
                        dy = best.second.toDouble(),
                        error = best.third,
                    )
                }
            }
        }

        var accepted = FrameTransform2D()
        var residual = 0.0
        var confidence = 0.0
        var rotationDeg = 0.0
        var scale = 1.0
        var model = MotionModel.NONE

        if (shifts.size >= config.minAcceptedPatches) {
            val medianDx = median(shifts.map { it.dx })
            val medianDy = median(shifts.map { it.dy })
            val translationResiduals = shifts.map { hypot(it.dx - medianDx, it.dy - medianDy) }
            val medianTranslationResidual = median(translationResiduals)
            val looseGate = max(config.maxResidualPx * 2.0, 2.0 * medianTranslationResidual + 2.0)
            val translationInliers = shifts.filter { hypot(it.dx - medianDx, it.dy - medianDy) <= looseGate }

            if (translationInliers.size >= config.minAcceptedPatches) {
                val tdx = median(translationInliers.map { it.dx })
                val tdy = median(translationInliers.map { it.dy })
                val translationResidual = median(translationInliers.map { hypot(it.dx - tdx, it.dy - tdy) })
                accepted = FrameTransform2D(tx = tdx, ty = tdy, varianceAdd = translationResidual * translationResidual * 0.25)
                residual = translationResidual
                model = MotionModel.TRANSLATION

                if (config.similarityEnabled && shifts.size >= config.minSimilarityPatches) {
                    val similarityCandidateCount = max(config.minSimilarityPatches, (shifts.size + 1) / 2)
                    val similarityCandidates = shifts.sortedBy { it.error }.take(similarityCandidateCount)
                    val initialFit = fitSimilarity(similarityCandidates)
                    if (initialFit != null) {
                        val fitResiduals = similarityCandidates.map { similarityResidual(initialFit.transform, it) }
                        val med = median(fitResiduals)
                        val gate = max(config.maxResidualPx, 2.0 * med + 1.0)
                        val inliers = similarityCandidates.filter { similarityResidual(initialFit.transform, it) <= gate }
                        val refined = if (inliers.size >= config.minSimilarityPatches) fitSimilarity(inliers) else null
                        if (refined != null) {
                            val sameSetTranslationDx = median(inliers.map { it.dx })
                            val sameSetTranslationDy = median(inliers.map { it.dy })
                            val sameSetTranslationResidual = median(inliers.map {
                                hypot(it.dx - sameSetTranslationDx, it.dy - sameSetTranslationDy)
                            })
                            val rotationOk = abs(refined.rotationDeg) <= config.maxRotationDegPerFrame
                            val scaleOk = abs(refined.scale - 1.0) <= config.maxScaleDeltaPerFrame
                            val meaningfulGeometry = abs(refined.rotationDeg) >= config.minRotationDegForSimilarity ||
                                abs(refined.scale - 1.0) >= config.minScaleDeltaForSimilarity
                            val improved = refined.residualPx <= max(0.35, sameSetTranslationResidual * config.similarityResidualRatio)
                            if (rotationOk && scaleOk && meaningfulGeometry && improved) {
                                accepted = refined.transform.copy(varianceAdd = refined.residualPx * refined.residualPx * 0.25)
                                residual = refined.residualPx
                                rotationDeg = refined.rotationDeg
                                scale = refined.scale
                                model = MotionModel.SIMILARITY
                            }
                        }
                    }
                }

                val support = when (model) {
                    MotionModel.SIMILARITY -> {
                        val candidateCount = max(config.minSimilarityPatches, (shifts.size + 1) / 2)
                        candidateCount.toDouble() / shifts.size.toDouble()
                    }
                    else -> translationInliers.size.toDouble() / shifts.size.toDouble()
                }
                val residualTerm = (1.0 - residual / max(config.maxResidualPx, 1e-6)).coerceIn(0.0, 1.0)
                confidence = support * (0.45 + 0.55 * residualTerm)
                if (confidence < config.minConfidence) {
                    accepted = FrameTransform2D()
                    rotationDeg = 0.0
                    scale = 1.0
                    model = MotionModel.NONE
                }
            }
        }

        if (confidence >= config.minConfidence) {
            referenceToCurrent = composeAffine(accepted, referenceToCurrent)
        }
        copyFrame(frame)

        return MotionHint(
            previousToCurrent = if (confidence >= config.minConfidence) accepted else FrameTransform2D(),
            currentToStabilized = inverseAffine(referenceToCurrent),
            confidence = confidence,
            residualPx = residual,
            rotationDeg = rotationDeg,
            scale = scale,
            model = model,
        )
    }

    fun seed(frame: GrayFrame) {
        if (frame.width != width || frame.height != height || previous.size != frame.width * frame.height) {
            width = frame.width
            height = frame.height
            previous = ByteArray(width * height)
            referenceToCurrent = FrameTransform2D()
        }
        copyFrame(frame)
    }

    private fun fitSimilarity(shifts: List<Shift>): SimilarityFit? {
        if (shifts.size < 2) return null
        val px = shifts.map { it.x }.average()
        val py = shifts.map { it.y }.average()
        val qx = shifts.map { it.x + it.dx }.average()
        val qy = shifts.map { it.y + it.dy }.average()

        var denom = 0.0
        var aa = 0.0
        var bb = 0.0
        for (s in shifts) {
            val x = s.x - px
            val y = s.y - py
            val u = s.x + s.dx - qx
            val v = s.y + s.dy - qy
            denom += x * x + y * y
            aa += x * u + y * v
            bb += x * v - y * u
        }
        if (!denom.isFinite() || denom < 1e-6) return null
        val a = aa / denom
        val b = bb / denom
        val scale = sqrt(a * a + b * b)
        if (!scale.isFinite() || scale < 1e-6) return null
        val tx = qx - a * px + b * py
        val ty = qy - b * px - a * py
        val transform = FrameTransform2D(a00 = a, a01 = -b, tx = tx, a10 = b, a11 = a, ty = ty)
        val residual = median(shifts.map { similarityResidual(transform, it) })
        val gate = max(config.maxResidualPx, 2.0 * residual + 1.0)
        val inliers = shifts.count { similarityResidual(transform, it) <= gate }
        return SimilarityFit(
            transform = transform,
            rotationDeg = atan2(b, a) * 180.0 / PI,
            scale = scale,
            residualPx = residual,
            inlierCount = inliers,
        )
    }

    private fun similarityResidual(transform: FrameTransform2D, shift: Shift): Double {
        val mapped = transform.transformPoint(shift.x, shift.y)
        return hypot(mapped.first - (shift.x + shift.dx), mapped.second - (shift.y + shift.dy))
    }

    private fun composeAffine(step: FrameTransform2D, cumulative: FrameTransform2D): FrameTransform2D = FrameTransform2D(
        a00 = step.a00 * cumulative.a00 + step.a01 * cumulative.a10,
        a01 = step.a00 * cumulative.a01 + step.a01 * cumulative.a11,
        tx = step.a00 * cumulative.tx + step.a01 * cumulative.ty + step.tx,
        a10 = step.a10 * cumulative.a00 + step.a11 * cumulative.a10,
        a11 = step.a10 * cumulative.a01 + step.a11 * cumulative.a11,
        ty = step.a10 * cumulative.tx + step.a11 * cumulative.ty + step.ty,
        varianceAdd = step.varianceAdd + cumulative.varianceAdd,
    )

    private fun inverseAffine(t: FrameTransform2D): FrameTransform2D {
        val det = t.a00 * t.a11 - t.a01 * t.a10
        if (!det.isFinite() || abs(det) < 1e-9) return FrameTransform2D(valid = false)
        val i00 = t.a11 / det
        val i01 = -t.a01 / det
        val i10 = -t.a10 / det
        val i11 = t.a00 / det
        return FrameTransform2D(
            a00 = i00,
            a01 = i01,
            tx = -(i00 * t.tx + i01 * t.ty),
            a10 = i10,
            a11 = i11,
            ty = -(i10 * t.tx + i11 * t.ty),
            varianceAdd = t.varianceAdd,
        )
    }

    private fun bestShift(frame: GrayFrame, cx: Int, cy: Int, patchR: Int, searchR: Int): Triple<Int, Int, Double>? {
        val step = config.coarseStepPx.coerceAtLeast(1)
        var bestDx = 0
        var bestDy = 0
        var bestError = Double.POSITIVE_INFINITY
        var dy = -searchR
        while (dy <= searchR) {
            var dx = -searchR
            while (dx <= searchR) {
                val error = normalizedSad(frame, cx, cy, cx + dx, cy + dy, patchR)
                if (error < bestError) {
                    bestError = error
                    bestDx = dx
                    bestDy = dy
                }
                dx += step
            }
            dy += step
        }
        val refine = max(1, step - 1)
        for (yy in bestDy - refine..bestDy + refine) for (xx in bestDx - refine..bestDx + refine) {
            if (abs(xx) > searchR || abs(yy) > searchR) continue
            val error = normalizedSad(frame, cx, cy, cx + xx, cy + yy, patchR)
            if (error < bestError) {
                bestError = error
                bestDx = xx
                bestDy = yy
            }
        }
        return if (bestError.isFinite()) Triple(bestDx, bestDy, bestError) else null
    }

    private fun normalizedSad(frame: GrayFrame, px: Int, py: Int, cx: Int, cy: Int, r: Int): Double {
        if (cx - r < 0 || cy - r < 0 || cx + r >= width || cy + r >= height) return Double.POSITIVE_INFINITY
        var prevMean = 0.0
        var curMean = 0.0
        var n = 0
        for (yy in -r..r) for (xx in -r..r) {
            prevMean += previous[(py + yy) * width + (px + xx)].toInt() and 0xff
            curMean += frame.u8(cx + xx, cy + yy)
            n++
        }
        prevMean /= n
        curMean /= n
        var sad = 0.0
        for (yy in -r..r) for (xx in -r..r) {
            val a = (previous[(py + yy) * width + (px + xx)].toInt() and 0xff) - prevMean
            val b = frame.u8(cx + xx, cy + yy) - curMean
            sad += abs(a - b)
        }
        return sad / n
    }

    private fun patchRange(cx: Int, cy: Int, r: Int): Int {
        var lo = 255
        var hi = 0
        for (yy in -r..r) for (xx in -r..r) {
            val v = previous[(cy + yy) * width + (cx + xx)].toInt() and 0xff
            if (v < lo) lo = v
            if (v > hi) hi = v
        }
        return hi - lo
    }

    private fun copyFrame(frame: GrayFrame) {
        if (frame.rowStride == width) {
            System.arraycopy(frame.pixels, 0, previous, 0, width * height)
        } else {
            for (y in 0 until height) {
                System.arraycopy(frame.pixels, y * frame.rowStride, previous, y * width, width)
            }
        }
    }

    private fun median(values: List<Double>): Double {
        if (values.isEmpty()) return 0.0
        val a = values.sorted()
        val m = a.size / 2
        return if (a.size % 2 == 1) a[m] else 0.5 * (a[m - 1] + a[m])
    }
}
