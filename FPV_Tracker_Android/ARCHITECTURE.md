# Архитектура

## Поток данных
`CameraX -> gray frame -> camera motion -> target LK -> FB filter -> RANSAC affine -> quality gate -> TRACK`

При потере:
`TRACK -> SEARCH -> camera/temporal hint -> ORB local -> ORB global -> RANSAC -> REACQUIRED -> LK reseed -> TRACK`

## Модули
### MainActivity
Только camera lifecycle, передача кадров, ручной bbox и минимальный UI.

### CameraFrameConverter
Читает Y-plane CameraX с `rowStride/pixelStride`, приводит кадр к рабочей ориентации.

### CoordinateMapper
Преобразует bbox между analysis image и overlay. Текущая модель — FIT_CENTER; перед финальным APK обязательно проверить crop/orientation на Pixel 7a.

### GlobalMotionCompensator
Берёт feature points вне bbox цели, выполняет LK + FB check + RANSAC affine. Оценённое движение камеры используется как initial flow для точек цели.

### OpticalFlowTracker
Shi–Tomasi points внутри bbox, pyramidal LK, FB reject, RANSAC partial affine, bbox update, reseed.

### MotionModel
История нескольких bbox; median/newest delta для позиции и изменения размера. Один плохой кадр не должен определять прогноз.

### ReacquireEngine
Anchor + recent keyframe; ORB descriptors, ratio test, RANSAC geometry; local then global search.

### AdaptiveTracker
Единственный state machine: IDLE / TRACK / SEARCH / REACQUIRED.

## Правила безопасности от дрейфа
- anchor не перезаписывается до нового ручного захвата;
- recent обновляется только после качественных TRACK кадров;
- в SEARCH визуальная память не обучается;
- REACQUIRED подтверждается геометрией и успешным reseed LK.
