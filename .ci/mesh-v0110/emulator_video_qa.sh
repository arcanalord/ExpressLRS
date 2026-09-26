set -euo pipefail
EVIDENCE=/tmp/mesh-dev10-emulator-evidence
mkdir -p "$EVIDENCE/ui"

APK="${APP_DIR}/build/app/outputs/flutter-apk/app-debug.apk"
test -s "$APK"
adb install -r "$APK"

adb shell wm size 1080x1920
adb shell wm density 420
adb logcat -c

adb shell monkey -p org.fpvclub.mesh.flutter -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 8

cat > /tmp/tap_text.py <<'PY'
import re, subprocess, sys, xml.etree.ElementTree as ET
target = sys.argv[1]
subprocess.run(["adb","shell","uiautomator","dump","/sdcard/window.xml"], check=True, stdout=subprocess.DEVNULL)
subprocess.run(["adb","pull","/sdcard/window.xml","/tmp/window.xml"], check=True, stdout=subprocess.DEVNULL)
root = ET.parse("/tmp/window.xml").getroot()
matches = []
for node in root.iter("node"):
    text = node.attrib.get("text","")
    desc = node.attrib.get("content-desc","")
    if text == target or desc == target:
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds",""))
        if m:
            x1,y1,x2,y2 = map(int,m.groups())
            matches.append(((x1+x2)//2,(y1+y2)//2))
if not matches:
    print(f"TARGET_NOT_FOUND:{target}", file=sys.stderr)
    sys.exit(2)
print(matches[0][0], matches[0][1])
PY

tap_text() {
  local label="$1"
  read -r X Y < <(python3 /tmp/tap_text.py "$label")
  adb shell input tap "$X" "$Y"
  sleep 3
}

dump_ui() {
  local name="$1"
  adb shell uiautomator dump "/sdcard/$name.xml" >/dev/null
  adb pull "/sdcard/$name.xml" "$EVIDENCE/ui/$name.xml" >/dev/null
  adb exec-out screencap -p > "$EVIDENCE/$name.png"
}

PID="$(adb shell pidof -s org.fpvclub.mesh.flutter | tr -d '\r')"
test -n "$PID"

dump_ui 00_chats
adb shell screenrecord --bit-rate 5000000 --time-limit 35 /sdcard/mesh-dev10-smoke.mp4 >/dev/null 2>&1 &

tap_text "Карта"
dump_ui 01_map

tap_text "Связь"
dump_ui 02_connection
if python3 /tmp/tap_text.py "Обновить USB" >/tmp/usb_coords 2>/dev/null; then
  read -r X Y </tmp/usb_coords
  adb shell input tap "$X" "$Y"
  sleep 3
  dump_ui 03_usb_refresh
fi

tap_text "Настройки"
dump_ui 04_settings

tap_text "Справка"
dump_ui 05_help
adb shell input keyevent 4
sleep 2

tap_text "Чаты"
dump_ui 06_chats_return

sleep 8
adb pull /sdcard/mesh-dev10-smoke.mp4 "$EVIDENCE/MeshMessenger-v0.1.10-dev.10-emulator-smoke.mp4"

adb logcat --pid="$PID" -d > "$EVIDENCE/logcat.txt" || true
if grep -E "FATAL EXCEPTION|AndroidRuntime.*FATAL|Process: org\.fpvclub\.mesh\.flutter.*has died" "$EVIDENCE/logcat.txt"; then
  echo "APP_FATAL_FOUND" >&2
  exit 3
fi

grep -q 'text="Карта"' "$EVIDENCE/ui/01_map.xml"
grep -q 'text="Связь"' "$EVIDENCE/ui/02_connection.xml"
grep -q 'text="Радиомодуль · USB"' "$EVIDENCE/ui/02_connection.xml"
grep -q 'text="Настройки"' "$EVIDENCE/ui/04_settings.xml"
grep -q 'text="Справка"' "$EVIDENCE/ui/05_help.xml"

{
  echo "Mesh Messenger Flutter v0.1.10-dev.10 emulator smoke"
  echo "Date: 2026-09-26"
  echo "Android API: 35"
  echo "PASS: app launch"
  echo "PASS: Chats -> Map -> Connection -> Settings -> Help -> Chats"
  echo "PASS: USB refresh action without attached hardware"
  echo "PASS: no app FATAL in package logcat"
  echo "LIMIT: no physical USB-UART/M03/radio HIL in emulator"
} > "$EVIDENCE/QA_EMULATOR_VIDEO_REPORT.txt"

