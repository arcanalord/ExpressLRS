package club.fpv.aicv.contracts

data class MotionPrediction(
    val box: CvBox,
    val vx: Float,
    val vy: Float,
    val vScale: Float
)

interface MotionPredictor {
    fun reset(box: CvBox)
    fun predict(timestampNs: Long): MotionPrediction
    fun correct(measured: CvBox, timestampNs: Long)
}

data class AppearanceScore(
    val anchor: Float,
    val stable: Float,
    val adaptive: Float,
    val best: Float
)

interface AppearanceModel {
    fun initialize(frame: GrayFrame, box: CvBox)
    fun score(frame: GrayFrame, box: CvBox): AppearanceScore
    fun updateConfirmed(frame: GrayFrame, box: CvBox, confidence: Float)
    fun restoreStable()
}

interface LocalTracker {
    fun track(frame: GrayFrame, predicted: MotionPrediction): TrackObservation
}

interface QualityGate {
    fun classify(
        appearance: AppearanceScore,
        featureSurvival: Float,
        flowError: Float,
        geometryConfidence: Float
    ): Pair<TrackState, String>
}
