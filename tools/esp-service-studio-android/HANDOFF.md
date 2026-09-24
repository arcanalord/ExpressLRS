# ESP Service Studio — HANDOFF v0.7.0

Дата: 2026-09-24

## Основное
- Рабочая ветка сборки: arcanalord/ExpressLRS, branch esp-service-studio-android.
- GitHub используется как сборочная площадка.
- Основное пользовательское хранилище релизов и документации: Dropbox /Программы/ESP Service Studio.
- Patch-builder: tools/esp-service-studio-android/apply_patch.py.

## База v0.6, сохранённая в v0.7
- Ручной BOOT без RESET/stub для однокнопочных плат.
- ROM flashing с безопасным блоком 0x400.
- Проверка устройства: USB -> ROM sync -> chip -> Flash ID/size.
- Автовыбор безопасного preset по BOOTLOADER_FLASH_OFFSET.
- ESP8266/ESP8285 single-image preset.
- Проверка физического размера flash перед записью.
- IMAGE_OUT_OF_FLASH блокирует выход образа за границы памяти.
- Выбранные пользователем файлы/кастомная раскладка не перетираются.
- Нативные serial read/write ошибки выводятся в UI.
- Диагностические коды USB_OK, ROM_SYNC_OK, ROM_SYNC_TIMEOUT, FLASH_ID_FAIL,
  PREFLIGHT_FAIL, WRITE_TIMEOUT, WRITE_OK, FLASH_BOUNDS_OK и другие.
- esptool-js 0.7.0, usb-serial-for-android 3.11.0.
- Kotlin runtime 1.9.22, androidx.annotation 1.8.2.

## Новое в v0.7
- Кнопка Экспорт в панели диагностического лога.
- Экспорт через стандартный Android share sheet / сохранение.
- В экспорт входят дата, USB-устройство, VID:PID, профиль адаптера, preset,
  режим ручного BOOT и весь экранный диагностический лог.
- Распознавание известных USB-профилей:
  - WCH CH340/CH341
  - Silicon Labs CP210x
  - FTDI USB-UART
  - Espressif native USB
- Диагностический код USB_PROFILE.
- ROM write path намеренно не менялся.

## Сборка
- versionName: 0.7.0
- versionCode: 7
- package: com.arcanalord.espservicestudio.debug
- targetSdk: 36
- minSdk: 22
- APK: ESP_Service_Studio_Pixel7a_v0.7.apk
- SHA256 APK: d40e3c89cc64826973d352250dc72cf7dfe6f8b171b3d5381e398ae11a77b83b
- apksigner: PASS
- v1 signature: true
- v2 signature: true
- signing: Android Debug

## CI
- Workflow run 36037174082.
- Job esp-service-studio-apk: SUCCESS.
- Общий workflow может показывать failure из-за не относящихся к приложению
  matrix-сборок ExpressLRS; это не означает ошибку APK ESP Service Studio.

## Что проверить на телефоне
1. CH340/CH341 + ESP8266/ESP8285:
   Проверить устройство -> ROM sync -> chip -> Flash ID/size.
2. ESP32-C3/S3 native USB:
   тот же probe.
3. Ручной BOOT:
   отключить USB, держать BOOT, подключить USB/питание, отпустить BOOT.
4. Неверно большой bin должен блокироваться до записи кодом IMAGE_OUT_OF_FLASH.
5. Реальная прошивка тестового bin.
6. После проверки нажать Экспорт и сохранить диагностический лог.

## Правило хранения
- Dropbox является основным пользовательским архивом.
- Каждый релиз должен иметь один релизный пакет без дублей.
- Старую подтверждённо рабочую версию не удалять до аппаратной проверки новой.
- Мусор/временные артефакты не хранить в корне проекта.
