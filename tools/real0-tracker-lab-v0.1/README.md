# Real-0 Android Tracker Lab v0.1.5

Corrective build after v0.1.4 compiled but failed real phone tracking.

## Root causes fixed
- CAMERA display and tracker now use the same rotated ImageAnalysis frame; the separate PreviewView transform was removed.
- CameraX RGBA rowStride/padding is handled before crop/rotation.
- The shared core again follows the Real-0 v0.4 supervisor design: multi-scale local search, guarded target model, QualityGate, prediction, LOST/SEARCHING, and full-frame reacquire with two-frame confirmation.
- Android analysis is reduced to 320 px width and converted with bulk getPixels(), rather than repeated Bitmap.getPixel() on full-resolution frames.
- QUICK/PRECISE LOCK freezes the exact displayed frame before tracker init.

## Core smoke
The JVM replay now covers:
1. fast translation;
2. scale change;
3. occlusion to LOST/SEARCHING;
4. far reappearance and full-frame reacquire;
5. reset to IDLE.

Version: 0.1.5
Version code: 6
Package: club.fpv.real0.trackerlab

v0.1.4 remains build-valid but PHONE_FAIL and is not a runtime baseline.
