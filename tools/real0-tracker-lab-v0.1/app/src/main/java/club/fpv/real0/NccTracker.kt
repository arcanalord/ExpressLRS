package club.fpv.real0

import android.graphics.Bitmap
import android.graphics.RectF
import club.fpv.real0.core.BoxF
import club.fpv.real0.core.GrayFrame
import club.fpv.real0.core.NccTrackerCore

class NccTracker {
    private val core = NccTrackerCore()

    val policy: String get() = core.policy
    val modelUpdates: Int get() = core.modelUpdates
    val modelRestores: Int get() = core.modelRestores

    fun reset() = core.reset()

    fun init(frame: Bitmap, initial: RectF) {
        core.init(BitmapGrayFrame(frame), initial.toCore())
    }

    fun update(frame: Bitmap): TrackerResult {
        val r = core.update(BitmapGrayFrame(frame))
        return TrackerResult(
            state = TrackState.valueOf(r.state.name),
            measuredBox = r.measuredBox?.toAndroid(),
            predictedBox = r.predictedBox?.toAndroid(),
            quality = r.quality,
            processingMs = r.processingMs,
            reason = r.reason
        )
    }
}

private class BitmapGrayFrame(private val bitmap: Bitmap) : GrayFrame {
    override val width: Int get() = bitmap.width
    override val height: Int get() = bitmap.height

    override fun gray(x: Int, y: Int): Float {
        val c = bitmap.getPixel(x, y)
        return (0.299f * ((c shr 16) and 255) +
            0.587f * ((c shr 8) and 255) +
            0.114f * (c and 255)) / 255f
    }
}

private fun RectF.toCore() = BoxF(left, top, right, bottom)
private fun BoxF.toAndroid() = RectF(left, top, right, bottom)
