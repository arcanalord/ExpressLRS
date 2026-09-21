from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
repo = Path(sys.argv[2])

# Replace translation-only image motion with image-only translation + bounded similarity.
old_motion = root / "core/src/main/kotlin/com/pointtrack/core/GlobalTranslationStabilizer.kt"
if old_motion.exists():
    old_motion.unlink()
new_motion_src = repo / "pointtrack_ci/v098/GlobalImageMotionStabilizer.kt"
new_motion_dst = root / "core/src/main/kotlin/com/pointtrack/core/GlobalImageMotionStabilizer.kt"
shutil.copyfile(new_motion_src, new_motion_dst)

config = root / "core/src/main/kotlin/com/pointtrack/core/Config.kt"
s = config.read_text(encoding="utf-8")
old = """data class MotionConfig(
    val enabled: Boolean = true,
    val searchRadiusPx: Int = 12,
    val coarseStepPx: Int = 4,
    val patchRadiusPx: Int = 2,
    val gridColumns: Int = 3,
    val gridRows: Int = 2,
    val minPatchRange: Int = 12,
    val minAcceptedPatches: Int = 2,
    val maxResidualPx: Double = 4.5,
    val minConfidence: Double = 0.26,
)
"""
new = """data class MotionConfig(
    val enabled: Boolean = true,
    val searchRadiusPx: Int = 12,
    val coarseStepPx: Int = 4,
    val patchRadiusPx: Int = 2,
    val gridColumns: Int = 3,
    val gridRows: Int = 2,
    val minPatchRange: Int = 12,
    val minAcceptedPatches: Int = 2,
    val maxResidualPx: Double = 4.5,
    val minConfidence: Double = 0.26,
    val similarityEnabled: Boolean = true,
    val minSimilarityPatches: Int = 4,
    val maxRotationDegPerFrame: Double = 4.0,
    val maxScaleDeltaPerFrame: Double = 0.05,
    val minRotationDegForSimilarity: Double = 0.10,
    val minScaleDeltaForSimilarity: Double = 0.003,
    val similarityResidualRatio: Double = 0.88,
)
"""
if old not in s:
    raise SystemExit("MotionConfig base block not found")
config.write_text(s.replace(old, new, 1), encoding="utf-8")

types = root / "core/src/main/kotlin/com/pointtrack/core/Types.kt"
s = types.read_text(encoding="utf-8")
old = """data class MotionHint(
    val previousToCurrent: FrameTransform2D = FrameTransform2D(),
    val currentToStabilized: FrameTransform2D = FrameTransform2D(),
    val confidence: Double = 0.0,
    val residualPx: Double = 0.0,
)
"""
new = """enum class MotionModel { NONE, TRANSLATION, SIMILARITY }

data class MotionHint(
    val previousToCurrent: FrameTransform2D = FrameTransform2D(),
    val currentToStabilized: FrameTransform2D = FrameTransform2D(),
    val confidence: Double = 0.0,
    val residualPx: Double = 0.0,
    val rotationDeg: Double = 0.0,
    val scale: Double = 1.0,
    val model: MotionModel = MotionModel.NONE,
)
"""
if old not in s:
    raise SystemExit("MotionHint base block not found")
types.write_text(s.replace(old, new, 1), encoding="utf-8")

runtime = root / "androidApp/src/main/java/com/fpvclub/pointtrack/TrackerRuntime.kt"
s = runtime.read_text(encoding="utf-8")
s = s.replace("import com.pointtrack.core.GlobalTranslationStabilizer", "import com.pointtrack.core.GlobalImageMotionStabilizer")
s = s.replace("import com.pointtrack.core.TrackState\n", "")
s = s.replace("import com.pointtrack.core.TrackingMode\n", "")
s = s.replace(
    "    val motionResidualPx: Double,\n",
    "    val motionResidualPx: Double,\n    val motionRotationDeg: Double,\n    val motionScale: Double,\n    val motionModel: String,\n",
)
s = s.replace(
    "    private val stabilizer: GlobalTranslationStabilizer = GlobalTranslationStabilizer(MotionConfig()),",
    "    private val stabilizer: GlobalImageMotionStabilizer = GlobalImageMotionStabilizer(MotionConfig()),",
)
for dead in (
    "    private var frameCounter = 0L\n",
    "    private var lastTrackingMode = TrackingMode.NONE\n",
    "    private var lastTrackState = TrackState.AIM\n",
    "        frameCounter = 0L\n",
    "        lastTrackingMode = TrackingMode.NONE\n",
    "        lastTrackState = TrackState.AIM\n",
):
    s = s.replace(dead, "")
s = s.replace(
"""        frameCounter++
        val stablePatchTrack = trackValid &&
            lastTrackingMode == TrackingMode.PATCH &&
            (lastTrackState == TrackState.LOCKED || lastTrackState == TrackState.INIT)
        val skipThisPatchMotionFrame = stablePatchTrack && frameCounter % 2L != 0L
        val estimateMotion = trackValid || command is TrackerCommand.Lock
""",
"""        val estimateMotion = trackValid || command is TrackerCommand.Lock
""",
)
s = s.replace(
"""        lastTrackingMode = result.track.trackingMode
        lastTrackState = result.track.state
""",
"",
)
old = """            motionResidualPx = motion.residualPx,
            lockRadiusPx = LOCK_RADIUS_PX,
"""
new = """            motionResidualPx = motion.residualPx,
            motionRotationDeg = motion.rotationDeg,
            motionScale = motion.scale,
            motionModel = motion.model.name,
            lockRadiusPx = LOCK_RADIUS_PX,
"""
if old not in s:
    raise SystemExit("AndroidTrackFrame motion output block not found")
runtime.write_text(s.replace(old, new, 1), encoding="utf-8")

main = root / "androidApp/src/main/java/com/fpvclub/pointtrack/MainActivity.kt"
s = main.read_text(encoding="utf-8")
old = """            "PointTrack v0.9.7-dev  %s\\n%s/%s  p %.2f a %.2f t %.2f  conf %.0f%%  miss %d  NIS %.1f  H %d\\nsize %.1f px  gate %.1f px  rescue %s\\nFPS %.1f  total %.1f ms  motion %.1f  det %.1f  patch %.1f  trk %.2f\\nmotion %+4.1f,%+4.1f q %.2f r %.1f | scan %s\\nevidence %d  hot -%d  static -%d/%d\\nIMM %.0f/%.0f/%.0f%%  temporal fast-path + bounded rescue / GYRO OFF",
"""
new = """            "PointTrack v0.9.8-dev  %s\\n%s/%s  p %.2f a %.2f t %.2f  conf %.0f%%  miss %d  NIS %.1f  H %d\\nsize %.1f px  gate %.1f px  rescue %s\\nFPS %.1f  total %.1f ms  motion %.1f  det %.1f  patch %.1f  trk %.2f\\nmotion %+4.1f,%+4.1f  rot %+3.2f°  scale %.3f  %s  q %.2f r %.1f | scan %s\\nevidence %d  hot -%d  static -%d/%d\\nIMM %.0f/%.0f/%.0f%%  image-only motion + bounded rescue",
"""
if old not in s:
    raise SystemExit("HUD format string not found")
s = s.replace(old, new, 1)
old = """            frame.motionDx,
            frame.motionDy,
            frame.motionConfidence,
            frame.motionResidualPx,
            frame.result.scanMode.name,
"""
new = """            frame.motionDx,
            frame.motionDy,
            frame.motionRotationDeg,
            frame.motionScale,
            frame.motionModel,
            frame.motionConfidence,
            frame.motionResidualPx,
            frame.result.scanMode.name,
"""
if old not in s:
    raise SystemExit("HUD motion args block not found")
main.write_text(s.replace(old, new, 1), encoding="utf-8")

reg = root / "core/src/test/kotlin/com/pointtrack/core/CoreRegression.kt"
s = reg.read_text(encoding="utf-8")
s = s.replace("import kotlin.math.abs\n", "import kotlin.math.abs\nimport kotlin.math.cos\nimport kotlin.math.roundToInt\nimport kotlin.math.sin\n", 1)
s = s.replace(
    "val stabilizer = GlobalTranslationStabilizer(MotionConfig(searchRadiusPx = 12, coarseStepPx = 3, minAcceptedPatches = 4))",
    "val stabilizer = GlobalImageMotionStabilizer(MotionConfig(searchRadiusPx = 12, coarseStepPx = 3, minAcceptedPatches = 4))",
    1,
)
needle = """    checkThat(mh.confidence > 0.25, "visual motion confidence regression")

"""
addition = """    checkThat(mh.confidence > 0.25, "visual motion confidence regression")

    // Pure image-only rotation/scale compensation. A small phone roll should be
    // represented as a similarity transform instead of being mistaken for target motion.
    fun transformedTextureFrame(width: Int, height: Int, angleDeg: Double, scale: Double, tx: Double, ty: Double, ts: Long): GrayFrame {
        val out = ByteArray(width * height)
        fun base(x: Int, y: Int): Int = (x * 17 + y * 29 + (x * y) % 73 + ((x xor y) * 3)) and 0xff
        val c = cos(angleDeg * Math.PI / 180.0)
        val ss = sin(angleDeg * Math.PI / 180.0)
        val cx = (width - 1) * 0.5
        val cy = (height - 1) * 0.5
        for (y in 0 until height) for (x in 0 until width) {
            val qx = x - tx - cx
            val qy = y - ty - cy
            val px = (c * qx + ss * qy) / scale + cx
            val py = (-ss * qx + c * qy) / scale + cy
            val ix = px.roundToInt()
            val iy = py.roundToInt()
            out[y * width + x] = (if (ix in 0 until width && iy in 0 until height) base(ix, iy) else 0).toByte()
        }
        return GrayFrame(width, height, width, ts, out)
    }
    val rotationStabilizer = GlobalImageMotionStabilizer(
        MotionConfig(searchRadiusPx = 12, coarseStepPx = 2, patchRadiusPx = 3, gridColumns = 4, gridRows = 3, minAcceptedPatches = 4, minSimilarityPatches = 5)
    )
    rotationStabilizer.update(transformedTextureFrame(320, 240, 0.0, 1.0, 0.0, 0.0, 0L))
    val rm = rotationStabilizer.update(transformedTextureFrame(320, 240, 1.5, 1.01, 3.0, -2.0, 33_333_333L))
    checkThat(rm.model == MotionModel.SIMILARITY, "image-only rotation model regression: $rm")
    checkThat(abs(rm.rotationDeg - 1.5) <= 0.7, "image-only rotation estimate regression: ${rm.rotationDeg}")
    checkThat(abs(rm.scale - 1.01) <= 0.025, "image-only scale estimate regression: ${rm.scale}")
    checkThat(rm.confidence > 0.25, "image-only similarity confidence regression")

"""
if needle not in s:
    raise SystemExit("rotation regression insertion point not found")
s = s.replace(needle, addition, 1)

needle = """    checkThat(patchHit2!!.temporalScore > 0.45 && patchHit2.anchorScore > 0.25, "dual-template temporal/anchor regression")

"""
addition = """    checkThat(patchHit2!!.temporalScore > 0.45 && patchHit2.anchorScore > 0.25, "dual-template temporal/anchor regression")

    // PATCH contrast is symmetric: dark-on-light and light-on-dark both initialize and track.
    fun invertFrame(src: GrayFrame): GrayFrame {
        val px = ByteArray(src.width * src.height)
        for (y in 0 until src.height) for (x in 0 until src.width) {
            px[y * src.width + x] = (255 - src.u8(x, y)).toByte()
        }
        return GrayFrame(src.width, src.height, src.width, src.timestampNs, px)
    }
    val brightPatch = PatchTemplateTracker(PatchTrackerConfig(lockedSearchRadiusPx = 40, coastSearchRadiusPx = 70, searchSearchRadiusPx = 90))
    val brightSeed = brightPatch.initialize(invertFrame(largeTargetFrame(80, 72, 0L)), 80.0, 72.0, 56.0)
    checkThat(brightSeed != null && brightSeed.polarity == 1, "bright-on-dark PATCH polarity regression")
    val brightHit = brightPatch.match(invertFrame(largeTargetFrame(92, 65, 33_333_333L)), 80.0, 72.0, TrackState.LOCKED)
    checkThat(brightHit != null && abs(brightHit.measurement.x - 92.0) <= 2.0 && abs(brightHit.measurement.y - 65.0) <= 2.0,
        "bright-on-dark PATCH tracking regression: $brightHit")
    checkThat(patchSeed!!.polarity == -1, "dark-on-light PATCH polarity regression")

"""
if needle not in s:
    raise SystemExit("PATCH polarity regression insertion point not found")
reg.write_text(s.replace(needle, addition, 1), encoding="utf-8")

gradle = root / "androidApp/build.gradle.kts"
s = gradle.read_text(encoding="utf-8")
s = s.replace("versionCode = 13", "versionCode = 14", 1)
s = s.replace('versionName = "0.9.5-dev"', 'versionName = "0.9.8-dev"', 1)
gradle.write_text(s, encoding="utf-8")

(root / "VERSION").write_text("0.9.8-dev\n", encoding="utf-8")

for name in ("README.md", "ANDROID_IMPLEMENTATION_REPORT.md"):
    p = root / name
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8")
    s = s.replace("PointTrack v0.9.5-dev", "PointTrack v0.9.8-dev")
    s = s.replace(
        "No gyroscope or IMU is used. `GYRO OFF` is shown in the engineering HUD.",
        "The runtime is image-only. No inertial-sensor runtime code is present in the Android path.",
    )
    s = s.replace(
        "Visual global translation remains image-only. Its default grid/search was reduced from the v0.9.3 configuration, and while a PATCH target is stably LOCKED the global-motion estimator runs every other frame; temporal patch tracking supplies the local frame-to-frame continuity in between.",
        "Global camera-motion compensation is image-only and runs on every active tracking frame. It always estimates translation and, when enough spatially distributed image patches support it, adds a bounded similarity residual (small rotation + uniform scale). This compensates phone pan/tilt/roll without inertial sensors.",
    )
    s = s.replace(
        "8. While a PATCH target is stably LOCKED/INIT, visual global motion is evaluated every other frame; the temporal patch tracker propagates the target on the intervening frame.",
        "8. Global image motion is evaluated on every active tracking frame. Translation is always available; a bounded image-only similarity residual (rotation + small scale) is used when it materially improves the fit.",
    )
    s = s.replace("explicit `GYRO OFF`.", "explicit image-only motion diagnostics.")
    s = s.replace("camera pan without gyro;", "camera pan/roll using image-only global motion;")
    p.write_text(s, encoding="utf-8")
