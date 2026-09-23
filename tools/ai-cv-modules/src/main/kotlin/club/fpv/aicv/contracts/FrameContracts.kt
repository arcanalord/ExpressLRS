package club.fpv.aicv.contracts

interface GrayFrame {
    val id: FrameId
    val timestampNs: Long
    val width: Int
    val height: Int
    val rotationDegrees: Int
    val sourceId: String
    fun gray(x: Int, y: Int): Float
}

interface FrameGeometry {
    fun displayPointToFrame(x: Float, y: Float): Pair<Float, Float>
    fun displayBoxToFrame(box: CvBox): CvBox
    fun frameBoxToDisplay(box: CvBox): CvBox
}
