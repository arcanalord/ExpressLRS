package com.fpvclub.pointtrack

import androidx.camera.core.ImageProxy
import com.pointtrack.core.EngineConfig
import com.pointtrack.core.EngineResult
import com.pointtrack.core.GrayFrame
import com.pointtrack.core.PointTrackEngine
import com.pointtrack.core.TrackerCommand
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicReference

internal data class AndroidTrackFrame(
    val result: EngineResult,
    val frameWidth: Int,
    val frameHeight: Int,
    val rotationDegrees: Int,
    val processingMs: Double,
    val fps: Double,
)

internal class TrackerRuntime(
    private val engine: PointTrackEngine = PointTrackEngine(EngineConfig()),
) {
    private val pendingCommand = AtomicReference<TrackerCommand>(TrackerCommand.None)
    private var packedY = ByteArray(0)
    @Volatile private var latestWidth = 0
    @Volatile private var latestHeight = 0
    @Volatile private var trackValid = false
    private var lastArrivalNs = 0L

    fun isTrackValid(): Boolean = trackValid

    fun lockCenter() {
        val w = latestWidth
        val h = latestHeight
        if (w > 0 && h > 0) {
            pendingCommand.set(TrackerCommand.Lock(w * 0.5, h * 0.5, radiusPx = 56.0))
        }
    }

    fun release() { pendingCommand.set(TrackerCommand.Release) }

    fun reset() {
        pendingCommand.set(TrackerCommand.None)
        engine.reset()
        trackValid = false
    }

    fun process(image: ImageProxy): AndroidTrackFrame? {
        val plane = image.planes.firstOrNull() ?: return null
        if (plane.pixelStride != 1) return null
        val crop = image.cropRect
        val width = crop.width()
        val height = crop.height()
        if (width <= 0 || height <= 0) return null
        latestWidth = width
        latestHeight = height
        ensurePackedBuffer(width * height)
        copyCroppedYPlane(plane.buffer, plane.rowStride, crop.left, crop.top, width, height, packedY)
        val frame = GrayFrame(width, height, width, image.imageInfo.timestamp, packedY)
        val now = System.nanoTime()
        val fps = if (lastArrivalNs == 0L) 0.0 else 1_000_000_000.0 / (now - lastArrivalNs).coerceAtLeast(1L)
        lastArrivalNs = now
        val started = System.nanoTime()
        val command = pendingCommand.getAndSet(TrackerCommand.None)
        val result = engine.processFrame(frame, motionHint = null, command = command)
        val processingMs = (System.nanoTime() - started) / 1_000_000.0
        trackValid = result.track.valid
        return AndroidTrackFrame(result, width, height, image.imageInfo.rotationDegrees, processingMs, fps)
    }

    private fun ensurePackedBuffer(size: Int) { if (packedY.size != size) packedY = ByteArray(size) }

    private fun copyCroppedYPlane(source: ByteBuffer,rowStride:Int,cropLeft:Int,cropTop:Int,width:Int,height:Int,target:ByteArray) {
        val src = source.duplicate(); src.rewind()
        val lastRow = cropTop + height - 1
        val required = lastRow * rowStride + cropLeft + width
        require(src.capacity() >= required) { "Y plane capacity " + src.capacity() + " < required " + required }
        for (y in 0 until height) {
            src.position((cropTop + y) * rowStride + cropLeft)
            src.get(target, y * width, width)
        }
    }
}
