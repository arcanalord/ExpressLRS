# Worklog — CURRENT

## 2026-09-19
### Выполнено
- Android закреплён как основная ветка.
- Рабочий захват: только ручной bbox.
- OpenCV dependency: 5.0.0.1; init через `OpenCVLoader.initLocal()`.
- CameraX: 1.6.2, analysis 640x480, KEEP_ONLY_LATEST.
- LK optical flow + forward-backward rejection.
- RANSAC partial affine для позиции/поворота/масштаба bbox.
- GlobalMotionCompensator по background points вне цели.
- Camera transform используется как initial target flow после рывка камеры.
- MotionModel переведён на многокадровую историю.
- ORB local/global reacquire сохраняет anchor + recent.
- Добавлены unit tests MotionModel / CoordinateMapper.
- Figma Android screen упрощён: камера, state, bbox, две основные кнопки, одна debug-строка.
- Номерная документация удалена; canonical filenames закреплены.
- Источник перенесён в `arcanalord/ExpressLRS`, ветка `fpv-tracker-android`.
- ExpressLRS `master` не изменяется.
- Добавлен GitHub Actions gate: Gradle help -> unit tests -> assembleDebug -> APK artifact.

### Проверено
- Pure Kotlin compile: PASS.
- Motion prediction smoke test: PASS.
- CoordinateMapper round-trip smoke test: PASS.
- OpenCV LK initial-flow API сверено с OpenCV 5 docs.
- CameraX 1.6.2 подтверждён как stable.

### Следующий gate
1. GitHub Actions full build.
2. Debug APK artifact.
3. APK на Pixel 7a.
4. Фиксированный сценарий: плавное движение, резкий рывок, масштаб, перекрытие, выход/возврат.
5. Решение о foreground/background validator по реальному логу.
