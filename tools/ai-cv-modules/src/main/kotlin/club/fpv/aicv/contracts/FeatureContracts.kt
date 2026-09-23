package club.fpv.aicv.contracts

data class FeaturePoint(
    val x: Float,
    val y: Float,
    val quality: Float,
    val id: Int
)

data class FeatureSet(
    val frameId: FrameId,
    val points: List<FeaturePoint>
)

data class FeatureTrackResult(
    val previous: FeatureSet,
    val current: FeatureSet,
    val survivedRatio: Float,
    val meanError: Float,
    val reason: String
)

interface FeatureExtractor {
    fun extract(frame: GrayFrame, box: CvBox): FeatureSet
}

interface FeatureTracker {
    fun track(previousFrame: GrayFrame, currentFrame: GrayFrame, features: FeatureSet): FeatureTrackResult
}
