package com.pointtrack.core

data class DetectorConfig(
    val backgroundRadius: Int = 5,
    val centroidRadius: Int = 1,
    val sigmaThreshold: Double = 4.7,
    val evidenceSigmaThreshold: Double = 2.2,
    val noiseFloor: Double = 2.0,
    val maxCandidates: Int = 128,
    val maxEvidenceCandidates: Int = 320,
    val minSeparationPx: Double = 2.5,
)

data class HotPixelConfig(
    val minHits: Int = 8,
    val forgetAfterFrames: Int = 900,
    val hotPeakFractionMin: Double = 0.78,
    val hotRadialMomentMax: Double = 0.32,
    val integerDistanceMax: Double = 0.20,
    val hardPeakFractionMin: Double = 0.90,
    val hardRadialMomentMax: Double = 0.12,
    val hardIntegerDistanceMax: Double = 0.10,
)

data class StaticClutterConfig(
    val minHits: Int = 6,
    val forgetAfterFrames: Int = 600,
    val matchRadiusPx: Double = 0.65,
    val updateAlpha: Double = 0.18,
)

data class TrackerConfig(
    val lockAfterHits: Int = 2,
    val maxCoastFrames: Int = 10,
    val maxSearchFrames: Int = 45,
    val reacquireConfirmHits: Int = 1,
    val initGatePx: Double = 36.0,
    val lockedGatePx: Double = 22.0,
    val coastGatePx: Double = 48.0,
    val searchGatePx: Double = 128.0,
    val velocityGateScale: Double = 0.75,
    val maxDynamicGatePx: Double = 180.0,
    val alpha: Double = 0.74,
    val beta: Double = 0.12,
    val minDtSeconds: Double = 1.0 / 240.0,
    val maxDtSeconds: Double = 0.25,
    val lockedRoiHalfSizePx: Int = 72,
    val coastRoiHalfSizePx: Int = 128,
    val searchRoiHalfSizePx: Int = 220,
)

data class EngineConfig(
    val detector: DetectorConfig = DetectorConfig(),
    val hotPixels: HotPixelConfig = HotPixelConfig(),
    val staticClutter: StaticClutterConfig = StaticClutterConfig(),
    val tracker: TrackerConfig = TrackerConfig(),
)
