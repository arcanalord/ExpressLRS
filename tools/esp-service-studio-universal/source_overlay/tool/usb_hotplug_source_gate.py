from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
native = Path('android/app/src/main/kotlin/com/arcanalord/service_studio/MainActivity.kt').read_text(encoding='utf-8')
manifest = Path('android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')
usb_filter = Path('android/app/src/main/res/xml/device_filter.xml').read_text(encoding='utf-8')

checks = {
    'poll fallback': 'Timer.periodic' in main and 'Duration(milliseconds: 800)' in main,
    'visible build id': 'v0.9.0-alpha.3 · Pixel 7a' in main,
    'localized profile': 'настройка и диагностика по SPI' in main and 'EP2 LINK' in main,
    'native attach': 'ACTION_USB_DEVICE_ATTACHED' in native,
    'native detach': 'ACTION_USB_DEVICE_DETACHED' in native,
    'new intent': 'onNewIntent' in native,
    'event channel': 'service_studio/usb_events' in native,
    'manifest attach': 'android.hardware.usb.action.USB_DEVICE_ATTACHED' in manifest,
    'manifest filter': '@xml/device_filter' in manifest,
    'WCH filter': 'vendor-id="6790"' in usb_filter,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('USB hotplug source gate failed: ' + ', '.join(failed))

print('USB hotplug source gate PASS')
