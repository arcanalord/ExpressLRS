from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')

if 'android.hardware.usb.host' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-feature android:name="android.hardware.usb.host" android:required="false" />',
    )

text = text.replace(
    'android:label="service_studio"',
    'android:label="ESP Service Studio"',
)

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

root_gradle = Path('android/build.gradle.kts')
gradle = root_gradle.read_text(encoding='utf-8')
if 'https://jitpack.io' not in gradle:
    old = '''    repositories {
        google()
        mavenCentral()
    }
'''
    new = '''    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
'''
    if old not in gradle:
        raise SystemExit('android/build.gradle.kts repositories block not found')
    gradle = gradle.replace(old, new, 1)
root_gradle.write_text(gradle, encoding='utf-8')

app_gradle = Path('android/app/build.gradle.kts')
app_text = app_gradle.read_text(encoding='utf-8')
dependency = 'implementation("com.github.mik3y:usb-serial-for-android:3.11.0")'
if dependency not in app_text:
    app_text += f'''\n\ndependencies {{
    {dependency}
}}
'''
app_gradle.write_text(app_text, encoding='utf-8')

final = manifest.read_text(encoding='utf-8')
for needle in [
    'android.hardware.usb.action.USB_DEVICE_ATTACHED',
    '@xml/device_filter',
    'ESP Service Studio',
]:
    if needle not in final:
        raise SystemExit(f'missing Android USB marker: {needle}')

if 'https://jitpack.io' not in root_gradle.read_text(encoding='utf-8'):
    raise SystemExit('JitPack repository patch missing')

if dependency not in app_gradle.read_text(encoding='utf-8'):
    raise SystemExit('usb-serial-for-android dependency missing')
