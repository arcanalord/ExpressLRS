package club.fpv.aicv.contracts

data class AutoFitResult(
    val box: CvBox?,
    val confidence: Float,
    val reason: String,
    val diagnostics: Map<String, Float> = emptyMap()
)

interface AutoFit {
    fun fit(frame: GrayFrame, seed: TargetSeed): AutoFitResult
}

data class StabilizationResult(
    val confirmed: Boolean,
    val box: CvBox?,
    val confidence: Float,
    val reason: String
)

interface LockStabilizer {
    fun reset(seed: TargetSeed, initial: AutoFitResult)
    fun update(frame: GrayFrame): StabilizationResult
}
