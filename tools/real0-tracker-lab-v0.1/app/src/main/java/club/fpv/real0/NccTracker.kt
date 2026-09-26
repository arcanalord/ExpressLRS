package club.fpv.real0

import android.graphics.Bitmap
import android.graphics.RectF
import club.fpv.real0.core.AutoFitCore
import club.fpv.real0.core.BoxF
import club.fpv.real0.core.GrayFrame
import club.fpv.real0.core.LockStabilizerCore
import club.fpv.real0.core.NccTrackerCore
import kotlin.math.min

class NccTracker {
    private val core = NccTrackerCore()
    private val autoFit = AutoFitCore()
    private val stabilizer = LockStabilizerCore(requiredFrames = 3)

    private var frameW = 0
    private var frameH = 0
    private var scale = 1f
    private var analysisWidthLimit = 320

    private var quickPending = false
    private var quickSeedX = 0f
    private var quickSeedY = 0f

    val policy: String get() = core.policy
    val modelUpdates: Int get() = core.modelUpdates
    val modelRestores: Int get() = core.modelRestores
    val isQuickPending: Boolean get() = quickPending
    val analysisWidth: Int get() = analysisWidthLimit

    fun reset() {
        core.reset()
        stabilizer.reset()
        quickPending = false
        frameW = 0
        frameH = 0
        scale = 1f
        analysisWidthLimit = 320
    }

    fun init(frame: Bitmap, initial: RectF, timestampNs: Long = 0L) {
        analysisWidthLimit = chooseAnalysisWidth(frame.width, initial.width())
        val p = prepare(frame, timestampNs)
        frameW = frame.width
        frameH = frame.height
        scale = p.scale
        quickPending = false
        stabilizer.reset()
        core.init(p.gray, initial.toCore(scale))
    }

    fun beginQuick(frame: Bitmap, seedX: Float, seedY: Float, timestampNs: Long = 0L): TrackerResult {
        core.reset()
        stabilizer.reset()

        // Bootstrap QUICK at higher resolution so small targets are not collapsed before AutoFit.
        analysisWidthLimit = 640
        var p = prepare(frame, timestampNs)
        frameW = frame.width
        frameH = frame.height
        scale = p.scale
        quickSeedX = seedX
        quickSeedY = seedY

        var fit = autoFit.fit(p.gray, seedX * scale, seedY * scale)
        var initial = fit.box
        if (initial == null) {
            quickPending = false
            return TrackerResult(TrackState.READY, null, null, 0f, 0f, "QUICK: AutoFit failed")
        }

        val targetSourceWidth = initial.width() / scale.coerceAtLeast(1e-6f)
        analysisWidthLimit = chooseAnalysisWidth(frame.width, targetSourceWidth)

        // Re-run at the locked analysis scale so stabilization and tracking use one geometry.
        p = prepare(frame, timestampNs)
        scale = p.scale
        fit = autoFit.fit(p.gray, seedX * scale, seedY * scale)
        initial = fit.box
        if (initial == null) {
            quickPending = false
            return TrackerResult(TrackState.READY, null, null, 0f, 0f, "QUICK: AutoFit rescale failed")
        }

        stabilizer.update(fit)
        quickSeedX = initial.centerX() / scale.coerceAtLeast(1e-6f)
        quickSeedY = initial.centerY() / scale.coerceAtLeast(1e-6f)
        quickPending = true

        return TrackerResult(
            state = TrackState.STABILIZING,
            measuredBox = initial.toAndroid(scale),
            predictedBox = null,
            quality = fit.confidence,
            processingMs = 0f,
            reason = "QUICK rough AutoFit @${analysisWidthLimit}px; waiting for stabilization"
        )
    }

    fun update(frame: Bitmap, timestampNs: Long = 0L): TrackerResult {
        val t0 = System.nanoTime()
        if (frameW != 0 && (frame.width != frameW || frame.height != frameH)) {
            reset()
            return TrackerResult(TrackState.LOST, null, null, 0f, 0f, "frame geometry changed")
        }

        val p = prepare(frame, timestampNs)
        scale = p.scale

        if (quickPending) {
            val fit = autoFit.fit(p.gray, quickSeedX * scale, quickSeedY * scale)
            val fitted = fit.box
            if (fitted != null) {
                quickSeedX = fitted.centerX() / scale.coerceAtLeast(1e-6f)
                quickSeedY = fitted.centerY() / scale.coerceAtLeast(1e-6f)
            }

            val stabilized = stabilizer.update(fit)
            val confirmed = stabilized.first
            val box = stabilized.second ?: fitted
            if (confirmed && box != null) {
                core.init(p.gray, box)
                quickPending = false
                return TrackerResult(
                    state = TrackState.TRACKING,
                    measuredBox = box.toAndroid(scale),
                    predictedBox = box.toAndroid(scale),
                    quality = fit.confidence,
                    processingMs = (System.nanoTime() - t0) / 1e6f,
                    reason = "QUICK stabilized and committed"
                )
            }

            return TrackerResult(
                state = TrackState.STABILIZING,
                measuredBox = box?.toAndroid(scale),
                predictedBox = null,
                quality = fit.confidence,
                processingMs = (System.nanoTime() - t0) / 1e6f,
                reason = "QUICK stabilizing"
            )
        }

        val r = core.update(p.gray)
        return TrackerResult(
            state = TrackState.valueOf(r.state.name),
            measuredBox = r.measuredBox?.toAndroid(scale),
            predictedBox = r.predictedBox?.toAndroid(scale),
            quality = r.quality,
            processingMs = (System.nanoTime() - t0) / 1e6f,
            reason = r.reason
        )
    }

    private fun prepare(bitmap: Bitmap, timestampNs: Long): Prepared {
        val s = min(1f, analysisWidthLimit.toFloat() / bitmap.width.toFloat())
        val w = (bitmap.width * s).toInt().coerceAtLeast(2)
        val h = (bitmap.height * s).toInt().coerceAtLeast(2)
        val work = if (s < 0.999f) Bitmap.createScaledBitmap(bitmap, w, h, true) else bitmap
        val pixels = IntArray(work.width * work.height)
        work.getPixels(pixels, 0, work.width, 0, 0, work.width, work.height)
        val gray = PixelGrayFrame(work.width, work.height, pixels, timestampNs)
        if (work !== bitmap) work.recycle()
        return Prepared(gray, s)
    }

    private fun chooseAnalysisWidth(frameWidth: Int, targetSourceWidth: Float): Int {
        if (targetSourceWidth <= 0f) return 320
        val desired = 18f * frameWidth / targetSourceWidth
        return when {
            desired <= 320f -> 320
            desired <= 480f -> 480
            else -> 640
        }
    }

    private data class Prepared(val gray: PixelGrayFrame, val scale: Float)
}

private class PixelGrayFrame(
    override val width: Int,
    override val height: Int,
    private val pixels: IntArray,
    override val timestampNs: Long
) : GrayFrame {
    override fun gray(x: Int, y: Int): Float {
        val c = pixels[y * width + x]
        return (0.299f * ((c shr 16) and 255) +
            0.587f * ((c shr 8) and 255) +
            0.114f * (c and 255)) / 255f
    }
}

private fun RectF.toCore(scale: Float) = BoxF(left * scale, top * scale, right * scale, bottom * scale)
private fun BoxF.toAndroid(scale: Float): RectF {
    val inv = 1f / scale.coerceAtLeast(1e-6f)
    return RectF(left * inv, top * inv, right * inv, bottom * inv)
}
