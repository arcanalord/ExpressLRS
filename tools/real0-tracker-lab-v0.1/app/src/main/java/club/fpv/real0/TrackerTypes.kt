package club.fpv.real0

import android.graphics.RectF

enum class TrackState { IDLE, READY, STABILIZING, TRACKING, UNCERTAIN, LOST, SEARCHING, REACQUIRED }

data class TrackerResult(
    val state: TrackState,
    val measuredBox: RectF?,
    val predictedBox: RectF?,
    val quality: Float,
    val processingMs: Float,
    val reason: String
)
