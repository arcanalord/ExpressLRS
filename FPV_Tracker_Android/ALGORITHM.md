# Алгоритм

## Temporal coherence
Соседний кадр рассматривается как предыдущий плюс движение камеры, относительное движение цели, масштаб/поворот и фотометрические изменения. Поэтому поиск с нуля каждый кадр не нужен.

## Компенсация движения камеры
Точки фона берутся вне расширенного bbox цели. По ним: LK -> backward LK -> FB reject -> RANSAC partial affine. Надёжная camera transform переносит initial target points в новый кадр до уточнения LK.

## Сопровождение цели
- Shi–Tomasi points внутри bbox;
- pyramidal LK;
- camera-seeded initial flow;
- forward-backward error;
- RANSAC affine;
- четыре угла bbox проходят через affine, поэтому рамка меняет центр и размер;
- периодический reseed points.

## Quality gate
TRACK зависит от набора сигналов: число точек, RANSAC inlier ratio, FB error, scale sanity. Один similarity score не используется как единственное доказательство.

## Многокадровый прогноз
MotionModel хранит историю bbox. Скорости `dx/dy/log(dw)/log(dh)` оцениваются устойчиво через median history с небольшим весом последнего delta.

## Reacquire
1. camera-propagated bbox или temporal prediction;
2. ORB anchor/recent в локальной области;
3. ratio test;
4. RANSAC affine verification;
5. при неудаче global search;
6. только затем reseed LK и REACQUIRED.

## Следующие измеряемые улучшения
Добавлять только после APK-теста на Pixel 7a:
- foreground/background validator;
- blur gate, запрещающий обновление памяти на смазанном кадре;
- небольшой appearance bank;
- lightweight embedding ReID для малотекстурных целей.
