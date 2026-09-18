package ru.fpvclub.tracker.tracking

data class Box(val x: Float, val y: Float, val w: Float, val h: Float) {
    val cx: Float get() = x + w * 0.5f
    val cy: Float get() = y + h * 0.5f
}

enum class TrackState { IDLE, TRACK, SEARCH, REACQUIRED }

data class TrackResult(
    val state: TrackState,
    val box: Box?,
    val quality: Float,
    val inlierRatio: Float,
    val points: Int,
    val mode: String = "IDLE",
    val scale: Float = 1f,
    val fbError: Float = 0f,
    val cameraInlierRatio: Float = 0f,
    val cameraPoints: Int = 0,
    val cameraDx: Float = 0f,
    val cameraDy: Float = 0f
)

data class ReacquireResult(
    val box: Box?,
    val quality: Float,
    val matches: Int,
    val inlierRatio: Float,
    val source: String
)
