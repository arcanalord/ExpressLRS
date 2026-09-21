from pathlib import Path
import sys

root = Path(sys.argv[1])

config = root / "core/src/main/kotlin/com/pointtrack/core/Config.kt"
s = config.read_text(encoding="utf-8")
replacements = {
    "val evidenceSigmaThreshold: Double = 2.2": "val evidenceSigmaThreshold: Double = 2.0",
    "val minCenterContrastSigma: Double = 0.65": "val minCenterContrastSigma: Double = 0.45",
    "val minCenterContrastAbs: Double = 10.0": "val minCenterContrastAbs: Double = 6.0",
    "val minTemplateEnergy: Double = 2200.0": "val minTemplateEnergy: Double = 1400.0",
    "val minCandidateEnergy: Double = 1300.0": "val minCandidateEnergy: Double = 800.0",
}
for old, new in replacements.items():
    if old not in s:
        raise SystemExit(f"missing config line: {old}")
    s = s.replace(old, new, 1)
config.write_text(s, encoding="utf-8")

engine = root / "core/src/main/kotlin/com/pointtrack/core/PointTrackEngine.kt"
s = engine.read_text(encoding="utf-8")
old = """                val point = bestPoint?.first
                val pointDistance = bestPoint?.second?.let { kotlin.math.sqrt(it) } ?: Double.POSITIVE_INFINITY
                val strongCentralPoint = point != null &&
                    point.effectiveRadiusPx <= 3.5 &&
                    point.snr >= 4.0 &&
                    pointDistance <= max(10.0, command.radiusPx * 0.28)

                val seed = patchSeed ?: if (strongCentralPoint) point else point
                if (seed != null) {
                    tracker.initialize(seed, frame.timestampNs)
                    result = tracker.estimate(frame.timestampNs)
                }
"""
new = """                val point = bestPoint?.first
                val pointDistance = bestPoint?.second?.let { kotlin.math.sqrt(it) } ?: Double.POSITIVE_INFINITY
                val strongCentralPoint = point != null &&
                    point.effectiveRadiusPx <= 3.5 &&
                    point.snr >= 3.0 &&
                    pointDistance <= max(12.0, command.radiusPx * 0.45)

                val fallbackX = command.x.coerceIn(0.0, (frame.width - 1).toDouble())
                val fallbackY = command.y.coerceIn(0.0, (frame.height - 1).toDouble())
                val fallback = Measurement(
                    x = fallbackX,
                    y = fallbackY,
                    snr = 2.5,
                    intensity = frame.u8(fallbackX.roundToInt(), fallbackY.roundToInt()).toDouble().coerceAtLeast(1.0),
                    positionVariance = 9.0,
                    sourceX = fallbackX,
                    sourceY = fallbackY,
                    source = MeasurementSource.POINT,
                    effectiveRadiusPx = 1.0,
                )
                val seed = patchSeed ?: if (strongCentralPoint) point!! else fallback
                tracker.initialize(seed, frame.timestampNs)
                result = tracker.estimate(frame.timestampNs)
"""
if old not in s:
    raise SystemExit("expected v0.9.5 lock seed block not found")
engine.write_text(s.replace(old, new, 1), encoding="utf-8")

reg = root / "core/src/test/kotlin/com/pointtrack/core/CoreRegression.kt"
r = reg.read_text(encoding="utf-8")
needle = """    checkThat(r.track.valid && r.track.state == TrackState.INIT, "LOCK did not initialize")
    checkThat(abs(r.track.x - 34.0) < 1.0, "LOCK did not snap to nearby real measurement")
    checkThat(r.scanMode == ScanMode.LOCK_ROI, "LOCK should use local ROI")
"""
addition = needle + """
    // Manual LOCK is authoritative: if neither PATCH nor point detector can seed,
    // preserve the pre-v0.9.4 behavior and start exactly at the requested point.
    val fallbackEngine = PointTrackEngine(
        EngineConfig(detector = DetectorConfig(evidenceSigmaThreshold = 100.0))
    )
    val fallbackLock = fallbackEngine.processFrame(
        frame(width = 96, height = 72, timestampNs = 1L),
        command = TrackerCommand.Lock(48.0, 36.0, 20.0),
    )
    checkThat(fallbackLock.track.valid && fallbackLock.track.state == TrackState.INIT, "manual center fallback regression")
    checkThat(abs(fallbackLock.track.x - 48.0) < 0.1 && abs(fallbackLock.track.y - 36.0) < 0.1, "manual fallback moved away from requested point")
"""
if needle not in r:
    raise SystemExit("manual fallback test insertion point not found")
r = r.replace(needle, addition, 1)

needle2 = """    // A single point target must remain POINT mode; a large patch tracker should not
"""
weak = """    // Low-contrast large manual target: contrast is intentionally below the old
    // 10-gray-level gate. Manual LOCK should still create a PATCH template.
    fun weakLargeTargetFrame(cx: Int, cy: Int, ts: Long): GrayFrame {
        val width = 192
        val height = 144
        val px = ByteArray(width * height)
        for (y in 0 until height) for (x in 0 until width) {
            val base = 128 + ((x * 5 + y * 3 + (x xor y)) % 11) - 5
            px[y * width + x] = base.coerceIn(0, 255).toByte()
        }
        for (y in cy - 20..cy + 20) for (x in cx - 20..cx + 20) {
            if (x !in 0 until width || y !in 0 until height) continue
            val dx = x - cx
            val dy = y - cy
            if (dx * dx + dy * dy <= 20 * 20) {
                val v = 120 + ((dx * 7 + dy * 11 + 200) % 13) - 6
                px[y * width + x] = v.coerceIn(0, 255).toByte()
            }
        }
        return GrayFrame(width, height, width, ts, px)
    }
    val weakPatch = PatchTemplateTracker()
    val weakSeed = weakPatch.initialize(weakLargeTargetFrame(80, 72, 0L), 80.0, 72.0, 56.0)
    checkThat(weakSeed != null && weakSeed.source == MeasurementSource.PATCH, "low-contrast manual PATCH initialization regression")
    val weakHit = weakPatch.match(weakLargeTargetFrame(88, 68, 33_333_333L), 80.0, 72.0, TrackState.LOCKED)
    checkThat(weakHit != null && abs(weakHit.measurement.x - 88.0) <= 3.0 && abs(weakHit.measurement.y - 68.0) <= 3.0,
        "low-contrast PATCH propagation regression: $weakHit")

"""
if needle2 not in r:
    raise SystemExit("low-contrast test insertion point not found")
r = r.replace(needle2, weak + needle2, 1)
reg.write_text(r, encoding="utf-8")

main = root / "androidApp/src/main/java/com/fpvclub/pointtrack/MainActivity.kt"
m = main.read_text(encoding="utf-8").replace("PointTrack v0.9.5-dev", "PointTrack v0.9.7-dev")
main.write_text(m, encoding="utf-8")

(root / "VERSION").write_text("0.9.7-dev\n", encoding="utf-8")
