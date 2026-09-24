from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')
if 'android.hardware.usb.host' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-feature android:name="android.hardware.usb.host" android:required="false" />',
    )
text = text.replace('android:label="service_studio"', 'android:label="ESP Service Studio"')
manifest.write_text(text, encoding='utf-8')
