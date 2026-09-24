# Mesh Messenger Flutter — карта как отдельный модуль

Версия правила: 2026-09-24

## Цель

Карта не должна ломать чат, транспорт, очередь сообщений или весь Flutter tree.
Любая ошибка карты должна деградировать только карту:
PMTiles -> OSM -> локальная сетка.

## Слои

1. MapPage
- только экран и композиция;
- получает точки от MeshAppController;
- открывает OfflineMapsSheet;
- после изменения карты меняет один reloadToken;
- не управляет внутренним состоянием bottom sheet.

2. OfflineMapsSheet
- отдельный StatefulWidget;
- импорт, выбор, отключение, удаление .pmtiles;
- собственные busy/error состояния;
- наружу возвращает только bool changed;
- не вызывает setState родительского MapPage.

3. AndroidMapPackagesBridge / AndroidMapSurface
- тонкий Flutter <-> Android bridge;
- MethodChannel без бизнес-логики;
- AndroidView пересоздаётся по ValueKey(reloadToken);
- handler обязательно снимается в dispose;
- точки передаются только после mapReady.

4. MapPackageStore.kt
- единственный владелец файлов .pmtiles;
- импорт через SAF;
- проверка размера и magic PMTiles;
- active map хранится отдельно;
- UI не знает физических путей файлов.

5. MapPlatformView.kt
- локальный https://app.local origin;
- отдаёт assets и range-запросы к active.pmtiles;
- никакой логики чатов/контактов;
- JS bridge только mapReady и mapTap.

6. map-runtime.js
- единственный renderer;
- читает metadata.vector_layers и сам выбирает существующие source-layer;
- PMTiles приоритет;
- если PMTiles не открывается и есть интернет -> лёгкая OSM raster;
- если интернета нет -> локальная сетка;
- точки/координаты работают во всех режимах.

## Запрещено

- StatefulBuilder для управления офлайн-картами из MapPage.
- Одновременно setState родителя и setSheetState после async.
- Жёстко считать, что PMTiles содержит конкретные layer names.
- Дублировать карту отдельным Flutter/Web/Android кодом без общего контракта.
- Делать карту зависимостью Core delivery, LAN, Meshtastic или USB transport.

## Обязательные gates перед APK

- flutter analyze
- flutter test
- core_self_test
- lan_transport_self_test
- map_point_self_test
- storage_concurrency_self_test
- map_source_gate
- map_vendor_gate
- Android build
- apksigner verify
- zipalign check

map_source_gate обязан проверять:
- OfflineMapsSheet выделен отдельно;
- ValueKey(reloadToken);
- снятие MethodChannel handler в dispose;
- mapReady handshake;
- PMTiles range requests;
- vector_layers autodetect;
- OSM fallback;
- локальная grid fallback.

## Ручной smoke test на телефоне

1. Открыть карту без PMTiles: должна появиться OSM при наличии сети или сетка без сети.
2. Импортировать Firenze .pmtiles.
3. Sheet закрывается без красного Flutter screen.
4. AndroidView пересоздаётся один раз.
5. Карта центрируется по metadata PMTiles.
6. Pan/pinch работают.
7. Тап по карте открывает создание MapPoint.
8. Переключить/отключить/удалить карту.
9. Вернуться в чат: сообщения и транспорт не должны измениться.
10. Повторить импорт 3 раза подряд — lifecycle exception недопустим.

## Правило дальнейшей разработки

Новая функция карты сначала добавляется в соответствующий слой, затем в map_source_gate,
и только после зелёного CI попадает в APK.
Core и transport не меняются ради UI-карты.
