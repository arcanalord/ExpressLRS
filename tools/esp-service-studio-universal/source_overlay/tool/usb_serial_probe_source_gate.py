from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')
native = Path(
    'android/app/src/main/kotlin/com/arcanalord/service_studio/MainActivity.kt'
).read_text(encoding='utf-8')
probe = Path(
    'android/app/src/main/kotlin/com/arcanalord/service_studio/UsbSerialProbe.kt'
).read_text(encoding='utf-8')
elrs = Path(
    'android/app/src/main/kotlin/com/arcanalord/service_studio/OfficialElrsService.kt'
).read_text(encoding='utf-8')
manifest = Path(
    'android/app/src/main/AndroidManifest.xml'
).read_text(encoding='utf-8')
app_gradle = Path(
    'android/app/build.gradle.kts'
).read_text(encoding='utf-8')
root_gradle = Path(
    'android/build.gradle.kts'
).read_text(encoding='utf-8')
device_profiles = Path(
    'assets/device_profiles.json'
).read_text(encoding='utf-8')

checks = {
    'visible alpha11 id': 'v0.9.0-alpha.11 · Pixel 7a' in main,
    'android package alpha11 id': 'version: 0.9.0-alpha.11+26092611' in pubspec,
    'real probe button': 'probeEspRom' in main,
    'permission request': 'requestPermission' in native,
    'permission result': 'ACTION_USB_PERMISSION' in native,
    'native probe': 'UsbSerialProbe(this).probe' in native,
    'ROM sync command': 'command(0x08, payload' in probe,
    'ESP8285 detect': 'ESP8285' in probe and '0xFFF0C101L' in probe,
    'chip read reg': '0x40001000L' in probe,
    'flash RDID': '0x9FL' in probe and 'Flash ID' in main,
    'manual ELRS safe DTR RTS': 'Do not touch DTR/RTS here' in probe,
    'WCH 55d3 fallback': '0x55D3' in probe,
    'CH34x driver': 'Ch34xSerialDriver' in probe,
    'usb serial dependency': 'usb-serial-for-android:3.11.0' in app_gradle,
    'jitpack': 'https://jitpack.io' in root_gradle,
    'USB attach manifest': 'USB_DEVICE_ATTACHED' in manifest,
    'official ELRS latest release': 'releases/latest' in elrs,
    'version pinned bundle': 'ensureBundle(' in elrs and 'firmware/hardware/targets.json' in elrs,
    'no master hardware': 'Targets/master' not in elrs,
    'dynamic official catalog': 'fetchCatalogIndex()' in elrs and 'collectTargets(' in elrs,
    'generic ELRS target guard': 'fetchCatalog(' in elrs and 'validateTargetPath(' in elrs,
    'official cache': 'artifactory.expresslrs.org' in elrs,
    'regional 900 support': 'FCC_915' in elrs and 'EU_868' in elrs and 'AU_915' in elrs and 'IN_866' in elrs,
    'regulatory domain channel': 'regulatoryDomain' in native and 'regulatoryProfile' not in native,
    'pinned hardware manifest proof': 'hardwareSource' in elrs and 'same firmware.zip commit' in elrs,
    'pinned hardware flash gate': 'hardwareSource' in probe and 'version-pinned hardware gate' in probe,
    'session commit pin': 'expectedCommitSha' in native and 'expectedCommitSha' in main and 'expectedCommitSha' in elrs,
    'binding phrase support': 'generateUid(' in elrs and 'bindingPhrase' in native,
    'wifi options': 'wifi-ssid' in elrs and 'wifiPassword' in native,
    'rx baud option': 'rcvr-uart-baud' in elrs and 'rxUartBaud' in native,
    'simple ELRS UI': '3. Настройки и прошивка' in main and 'Подготовить и прошить' in main,
    'prepare not flash': 'readyToFlash' in elrs and 'writeOffset' in elrs,
    'internet permission': 'android.permission.INTERNET' in manifest,
    'no hardcoded ELRS profiles': '"elrs"' not in device_profiles,
    'dynamic target UI': '2. ELRS оборудование' in main and "labelText: 'ELRS оборудование'" in main,
    'dynamic search UI': 'Поиск модели' in main,
    'MCU filtering': '_detectedPlatform' in main and '_filteredTargets' in main,
    'ESP8266 not aliased': "d.startsWith('esp8285')" in main and "d == 'esp8266ex'" in main,
    'catalog method channel': 'fetchOfficialElrsCatalogIndex' in native,
    'guarded flash method channel': 'flashPreparedEsp8285' in native and 'flashPrepared(' in probe,
    'prepared manifest': 'manifest.json' in elrs and 'manifestPath' in elrs,
    'ROM flash begin': 'FLASH_BEGIN' in probe and '0x02' in probe,
    'ROM flash data': '0x03' in probe and 'espChecksum' in probe,
    'ESP checksum seed': '0xEFL' in probe,
    'ESP8266 erase workaround': 'esp8266EraseSize' in probe,
    'flash target guard': 'expectedTargetPath' in probe and 'Unified_ESP8285_' in probe,
    'flash hash guard': 'SHA-256 firmware.bin' in probe and 'expectedSha256' in probe,
    'block ack disclaimer': 'Полный readback пока не выполнялся' in probe and 'полный readback содержимого пока не выполняется' in main,
    'generic ELRS ROM guidance': 'Для EP2' not in probe and 'ELRS оборудование' in probe,
    'real USB error text': r'\${' not in probe,
    'one action prepare then flash': '_prepareAndFlashElrs' in main and 'Подготовить и прошить' in main,
    'no forced EP2 default': 'selected ??= p.isEmpty ? null : p.first' not in main,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit(
        'USB serial probe source gate failed: ' + ', '.join(failed)
    )

print('USB serial + pinned ELRS bundle + guarded ESP8285 flash gate PASS')
