package ru.fpvclub.tracker.camera

import androidx.camera.core.ImageProxy
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Core

object CameraFrameConverter {
    /** Extracts the Y plane respecting CameraX rowStride/pixelStride, then rotates upright. */
    fun grayUpright(image: ImageProxy): Mat {
        val plane = image.planes[0]
        val buffer = plane.buffer.duplicate()
        val width = image.width; val height = image.height
        val rowStride = plane.rowStride; val pixelStride = plane.pixelStride
        val out = ByteArray(width * height)
        if (pixelStride == 1 && rowStride == width) {
            buffer.position(0); buffer.get(out, 0, minOf(out.size, buffer.remaining()))
        } else {
            for (y in 0 until height) {
                val rowStart = y * rowStride
                for (x in 0 until width) {
                    val pos = rowStart + x * pixelStride
                    if (pos < buffer.limit()) out[y * width + x] = buffer.get(pos)
                }
            }
        }
        val raw = Mat(height, width, CvType.CV_8UC1); raw.put(0,0,out)
        return when (image.imageInfo.rotationDegrees) {
            90 -> Mat().also { Core.rotate(raw, it, Core.ROTATE_90_CLOCKWISE); raw.release() }
            180 -> Mat().also { Core.rotate(raw, it, Core.ROTATE_180); raw.release() }
            270 -> Mat().also { Core.rotate(raw, it, Core.ROTATE_90_COUNTERCLOCKWISE); raw.release() }
            else -> raw
        }
    }
}
