package club.fpv.aicv.contracts

data class FrameId(val value: Long)

data class CvBox(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    val centerX: Float get() = (left + right) * 0.5f
    val centerY: Float get() = (top + bottom) * 0.5f
    val aspect: Float get() = width / height.coerceAtLeast(1e-6f)
}

enum class SeedType { POINT, BOX }

data class TargetSeed(
    val frameId: FrameId,
    val type: SeedType,
    val x: Float,
    val y: Float,
    val box: CvBox? = null
)

enum class TrackState {
    IDLE, READY, STABILIZING, TRACKING, UNCERTAIN, LOST, SEARCHING, REACQUIRE_CANDIDATE, REACQUIRED
}

data class TrackObservation(
    val frameId: FrameId,
    val state: TrackState,
    val measured: CvBox?,
    val predicted: CvBox?,
    val confidence: Float,
    val reason: String,
    val processingMs: Float
)
