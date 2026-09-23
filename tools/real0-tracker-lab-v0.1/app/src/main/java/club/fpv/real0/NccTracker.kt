package club.fpv.real0

import android.graphics.Bitmap
import android.graphics.RectF
import club.fpv.real0.core.BoxF
import club.fpv.real0.core.GrayFrame
import club.fpv.real0.core.NccTrackerCore
import kotlin.math.min

class NccTracker {
    private val core = NccTrackerCore()
    private var frameW = 0
    private var frameH = 0
    private var scale = 1f

    val policy: String get() = core.policy
    val modelUpdates: Int get() = core.modelUpdates
    val modelRestores: Int get() = core.modelRestores

    fun reset() {
        core.reset()
        frameW = 0
        frameH = 0
        scale = 1f
    }

    fun init(frame: Bitmap, initial: RectF) {
        val p = prepare(frame)
        frameW = frame.width
        frameH = frame.height
        scale = p.scale
        core.init(p.gray, initial.toCore(scale))
    }

    fun update(frame: Bitmap): TrackerResult {
        val t0 = System.nanoTime()
        if (frameW != 0 && (frame.width != frameW || frame.height != frameH)) {
            reset()
            return TrackerResult(TrackState.LOST, null, null, 0f, 0f, "frame geometry changed")
        }
        val p = prepare(frame)
        scale = p.scale
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

    private fun prepare(bitmap: Bitmap): Prepared {
        val s = min(1f, 320f / bitmap.width.toFloat())
        val w = (bitmap.width * s).toInt().coerceAtLeast(2)
        val h = (bitmap.height * s).toInt().coerceAtLeast(2)
        val work = if (s < 0.999f) Bitmap.createScaledBitmap(bitmap, w, h, true) else bitmap
        val pixels = IntArray(work.width * work.height)
        work.getPixels(pixels, 0, work.width, 0, 0, work.width, work.height)
        val gray = PixelGrayFrame(work.width, work.height, pixels)
        if (work !== bitmap) work.recycle()
        return Prepared(gray, s)
    }

    private data class Prepared(val gray: PixelGrayFrame, val scale: Float)
}

private class PixelGrayFrame(
    override val width: Int,
    override val height: Int,
    private val pixels: IntArray
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
