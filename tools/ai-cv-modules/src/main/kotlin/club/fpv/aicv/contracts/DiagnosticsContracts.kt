package club.fpv.aicv.contracts

data class TrackingTrace(
    val frameId: FrameId,
    val timestampNs: Long,
    val state: TrackState,
    val reason: String,
    val measured: CvBox?,
    val predicted: CvBox?,
    val candidate: CvBox?,
    val bboxScale: Float?,
    val bboxAspect: Float?,
    val vx: Float?,
    val vy: Float?,
    val vScale: Float?,
    val featureTotal: Int?,
    val featureSurvived: Int?,
    val flowError: Float?,
    val anchorScore: Float?,
    val stableScore: Float?,
    val adaptiveScore: Float?,
    val bestCandidateScore: Float?,
    val secondCandidateScore: Float?,
    val searchStage: SearchStage?,
    val processingMs: Float
)

interface TraceSink {
    fun record(trace: TrackingTrace)
}

interface EventRingBuffer {
    fun push(frame: GrayFrame, trace: TrackingTrace)
    fun snapshot(event: String): Any
}
