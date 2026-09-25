from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')

if 'android.hardware.usb.host' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-feature android:name="android.hardware.usb.host" android:required="false" />',
    )

text = text.replace('android:label="service_studio"', 'android:label="ESP Service Studio"')

if 'android.hardware.usb.action.USB_DEVICE_ATTACHED' not in text:
    attach = '''
            <intent-filter>
                <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
            </intent-filter>
            <meta-data
                android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
                android:resource="@xml/device_filter" />
'''
    pos = text.find('</activity>')
    if pos < 0:
        raise SystemExit('AndroidManifest.xml: activity closing tag not found')
    text = text[:pos] + attach + text[pos:]

manifest.write_text(text, encoding='utf-8')

device_filter = Path('android/app/src/main/res/xml/device_filter.xml')
if not device_filter.exists():
    raise SystemExit('device_filter.xml was not copied into Android resources')

final = manifest.read_text(encoding='utf-8')
for needle in [
    'android.hardware.usb.action.USB_DEVICE_ATTACHED',
    '@xml/device_filter',
    'ESP Service Studio',
]:
    if needle not in final:
        raise SystemExit(f'missing Android USB marker: {needle}')
