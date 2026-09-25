from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
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
    'visible alpha7 id': 'v0.9.0-alpha.7 · Pixel 7a' in main,
    'real probe button': 'probeEspRom' in main,
    'permission request': 'requestPermission' in native,
    'permission result': 'ACTION_USB_PERMISSION' in native,
    'native probe': 'UsbSerialProbe(this).probe' in native,
    'ROM sync command': 'command(0x08, payload' in probe,
    'ESP8285 detect': 'ESP8285' in probe and '0xFFF0C101L' in probe,
    'chip read reg': '0x40001000L' in probe,
    'flash RDID': '0x9FL' in probe and 'Flash ID' in main,
    'manual EP2 safe DTR RTS': 'Do not touch DTR/RTS here' in probe,
    'WCH 55d3 fallback': '0x55D3' in probe,
    'CH34x driver': 'Ch34xSerialDriver' in probe,
    'usb serial dependency': 'usb-serial-for-android:3.11.0' in app_gradle,
    'jitpack': 'https://jitpack.io' in root_gradle,
    'USB attach manifest': 'USB_DEVICE_ATTACHED' in manifest,
    'official ELRS latest release': 'releases/latest' in elrs,
    'generic ELRS target guard': 'fetchCatalog(' in elrs and 'validateSpec(' in elrs,
    'official cache': 'artifactory.expresslrs.org' in elrs,
    'prepare not flash': 'readyToFlash' in elrs and 'writeOffset' in elrs,
    'internet permission': 'android.permission.INTERNET' in manifest,
    'BETAFPV Nano profile': 'BETAFPV 2.4GHz Nano RX' in device_profiles,
    'BETAFPV official target path': 'betafpv.rx_2400.nano' in device_profiles,
    'EP2 official target path': 'happymodel.rx_2400.ep' in device_profiles,
    'no forced EP2 default': 'selected ??= p.isEmpty ? null : p.first' not in main,
    'manual target warning': 'ROM ESP8285 сам по себе' in main,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit(
        'USB serial probe source gate failed: ' + ', '.join(failed)
    )

print('USB serial + ESP8285 + ELRS multi-target source gate PASS')
