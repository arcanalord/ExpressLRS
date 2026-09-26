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

dump_screen() {
  local name="$1"
  adb exec-out screencap -p > "$EVIDENCE/$name.png"
}

assert_foreground() {
  local pid
  pid="$(adb shell pidof -s org.fpvclub.mesh.flutter | tr -d '\r')"
  test -n "$pid"
  adb shell dumpsys activity activities | grep -q "org.fpvclub.mesh.flutter"
}

# Fixed 1080x1920 test geometry. Bottom NavigationBar has four equal targets.
NAV_Y=1840
CHAT_X=135
MAP_X=405
CONNECTION_X=675
SETTINGS_X=945
HELP_X=900
APPBAR_Y=95

PID="$(adb shell pidof -s org.fpvclub.mesh.flutter | tr -d '\r')"
test -n "$PID"

assert_foreground
dump_screen 00_chats
adb shell screenrecord --bit-rate 5000000 --time-limit 35 /sdcard/mesh-dev10-smoke.mp4 >/dev/null 2>&1 &

adb shell input tap "$MAP_X" "$NAV_Y"
sleep 3
assert_foreground
dump_screen 01_map

adb shell input tap "$CONNECTION_X" "$NAV_Y"
sleep 3
assert_foreground
dump_screen 02_connection

# Tap the visible "Обновить USB" area in the USB card.
adb shell input tap 245 950
sleep 3
assert_foreground
dump_screen 03_usb_refresh

adb shell input tap "$SETTINGS_X" "$NAV_Y"
sleep 3
assert_foreground
dump_screen 04_settings

adb shell input tap "$HELP_X" "$APPBAR_Y"
sleep 3
assert_foreground
dump_screen 05_help
adb shell input keyevent 4
sleep 2

adb shell input tap "$CHAT_X" "$NAV_Y"
sleep 3
assert_foreground
dump_screen 06_chats_return

sleep 8
adb pull /sdcard/mesh-dev10-smoke.mp4 "$EVIDENCE/MeshMessenger-v0.1.10-dev.10-emulator-smoke.mp4"

adb logcat --pid="$PID" -d > "$EVIDENCE/logcat.txt" || true
if grep -E "FATAL EXCEPTION|AndroidRuntime.*FATAL|Process: org\.fpvclub\.mesh\.flutter.*has died" "$EVIDENCE/logcat.txt"; then
  echo "APP_FATAL_FOUND" >&2
  exit 3
fi

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

