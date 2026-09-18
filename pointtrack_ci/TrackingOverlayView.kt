package com.fpvclub.pointtrack

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import com.pointtrack.core.TrackState
import kotlin.math.max

internal class TrackingOverlayView(context: Context) : View(context) {
    private val aimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xCCFFFFFF.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF57E389.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }
    private val measurementPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFD166.toInt()
        style = Paint.Style.FILL
    }
    private val predictionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF5BC0EB.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }
    private val trailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x8857E389.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }
    private var frame: AndroidTrackFrame? = null
    private val trail = ArrayDeque<Pair<Double, Double>>()
    private var trailGeometry: Triple<Int, Int, Int>? = null

    fun update(value: AndroidTrackFrame) {
        val geometry = Triple(value.frameWidth, value.frameHeight, value.rotationDegrees)
        if (geometry != trailGeometry) {
            trail.clear()
            trailGeometry = geometry
        }
        val track = value.result.track
        if (track.valid) {
            trail.addLast(track.x to track.y)
            while (trail.size > 48) trail.removeFirst()
        } else if (track.state == TrackState.AIM || track.state == TrackState.LOST) {
            trail.clear()
        }
        frame = value
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        drawAim(canvas)
        val current = frame ?: return
        val track = current.result.track
        if (!track.valid) return

        if (trail.size > 1) {
            val path = Path()
            var first = true
            for ((x, y) in trail) {
                val p = mapPoint(x, y, current)
                if (first) {
                    path.moveTo(p.first, p.second)
                    first = false
                } else path.lineTo(p.first, p.second)
            }
            canvas.drawPath(path, trailPaint)
        }

        val tp = mapPoint(track.x, track.y, current)
        canvas.drawCircle(tp.first, tp.second, 18f, trackPaint)
        canvas.drawLine(tp.first - 26f, tp.second, tp.first - 10f, tp.second, trackPaint)
        canvas.drawLine(tp.first + 10f, tp.second, tp.first + 26f, tp.second, trackPaint)
        canvas.drawLine(tp.first, tp.second - 26f, tp.first, tp.second - 10f, trackPaint)
        canvas.drawLine(tp.first, tp.second + 10f, tp.first, tp.second + 26f, trackPaint)

        val measurementX = track.measurementX
        val measurementY = track.measurementY
        if (track.measuredThisFrame && measurementX != null && measurementY != null) {
            val mp = mapPoint(measurementX, measurementY, current)
            canvas.drawCircle(mp.first, mp.second, 5f, measurementPaint)
        }

        val predictedX = track.predictedX
        val predictedY = track.predictedY
        if (predictedX != null && predictedY != null) {
            val pp = mapPoint(predictedX, predictedY, current)
            canvas.drawRect(pp.first - 7f, pp.second - 7f, pp.first + 7f, pp.second + 7f, predictionPaint)
        }
    }

    private fun drawAim(canvas: Canvas) {
        val cx = width * 0.5f
        val cy = height * 0.5f
        canvas.drawCircle(cx, cy, 28f, aimPaint)
        canvas.drawLine(cx - 46f, cy, cx - 30f, cy, aimPaint)
        canvas.drawLine(cx + 30f, cy, cx + 46f, cy, aimPaint)
        canvas.drawLine(cx, cy - 46f, cx, cy - 30f, aimPaint)
        canvas.drawLine(cx, cy + 30f, cx, cy + 46f, aimPaint)
    }

    private fun mapPoint(x: Double, y: Double, frame: AndroidTrackFrame): Pair<Float, Float> {
        val fw = frame.frameWidth.toDouble()
        val fh = frame.frameHeight.toDouble()
        val rotation = ((frame.rotationDegrees % 360) + 360) % 360
        val (rx, ry, rw, rh) = when (rotation) {
            90 -> Quad(fh - 1.0 - y, x, fh, fw)
            180 -> Quad(fw - 1.0 - x, fh - 1.0 - y, fw, fh)
            270 -> Quad(y, fw - 1.0 - x, fh, fw)
            else -> Quad(x, y, fw, fh)
        }
        val scale = max(width / rw, height / rh)
        val dx = (width - rw * scale) * 0.5
        val dy = (height - rh * scale) * 0.5
        return ((rx * scale + dx).toFloat()) to ((ry * scale + dy).toFloat())
    }

    private data class Quad(val x: Double, val y: Double, val w: Double, val h: Double)
}
