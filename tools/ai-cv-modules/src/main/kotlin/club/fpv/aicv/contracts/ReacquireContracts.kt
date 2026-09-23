package club.fpv.aicv.contracts

enum class SearchStage { PREDICTION, EXPANDING_LOCAL, REGIONAL, FULL_FRAME }

data class ReacquireCandidate(
    val box: CvBox,
    val score: Float,
    val secondBestMargin: Float,
    val appearance: AppearanceScore,
    val geometryScore: Float,
    val motionScore: Float,
    val stage: SearchStage,
    val reason: String
)

interface ReacquireManager {
    fun reset(lastKnown: CvBox, timestampNs: Long)
    fun search(frame: GrayFrame, prediction: MotionPrediction?): List<ReacquireCandidate>
}

interface ConfirmationGate {
    fun reset()
    fun update(candidate: ReacquireCandidate?): Pair<Boolean, String>
}
