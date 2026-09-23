package club.fpv.aicv.contracts

data class ScaleEstimate(
    val scaleX: Float,
    val scaleY: Float,
    val confidence: Float,
    val reason: String
)

interface ScaleEstimator {
    fun estimate(previous: FeatureSet, current: FeatureSet, previousBox: CvBox): ScaleEstimate
}
