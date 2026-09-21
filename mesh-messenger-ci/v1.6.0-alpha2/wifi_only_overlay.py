#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: wifi_only_overlay.py <android-app-dir>")

root = Path(sys.argv[1]).resolve()
app_root = root / "app" / "src" / "main"
www = app_root / "assets" / "www"

def read(path):
    return path.read_text(encoding="utf-8")

def write(path, text):
    path.write_text(text, encoding="utf-8")

def replace_once(path, old, new, label):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match in {path}, got {count}")
    write(path, text.replace(old, new, 1))

def regex_once(path, pattern, replacement, label, flags=0):
    text = read(path)
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 regex match in {path}, got {count}")
    write(path, new_text)

build = root / "app" / "build.gradle.kts"
manifest = app_root / "AndroidManifest.xml"
app_js = www / "src" / "app.js"
core_js = www / "src" / "core.js"
help_js = www / "src" / "help-registry.js"
index_html = www / "index.html"
styles = www / "src" / "styles.css"
sw = www / "sw.js"

# Release identity.
replace_once(build, 'versionCode = 22', 'versionCode = 23', 'versionCode')
replace_once(build, 'versionName = "1.6.0-alpha1"', 'versionName = "1.6.0-alpha2"', 'versionName')

# Wi-Fi-only Android permissions: keep network + location for map/GPS; remove BLE requirements.
mtext = read(manifest)
for pattern in [
    r'^\s*<uses-feature android:name="android\.hardware\.bluetooth_le"[^>]*/>\s*\n',
    r'^\s*<uses-permission android:name="android\.permission\.BLUETOOTH"[^>]*/>\s*\n',
    r'^\s*<uses-permission android:name="android\.permission\.BLUETOOTH_ADMIN"[^>]*/>\s*\n',
    r'^\s*<uses-permission android:name="android\.permission\.BLUETOOTH_SCAN"[^>]*/>\s*\n',
    r'^\s*<uses-permission android:name="android\.permission\.BLUETOOTH_CONNECT"[^>]*/>\s*\n',
]:
    mtext = re.sub(pattern, '', mtext, flags=re.MULTILINE)
write(manifest, mtext)

# TransportManager remains extensible, but this build is allowed to select only Wi-Fi LAN.
replace_once(
    core_js,
    "const allowedIds = Array.isArray(meta.allowedTransportIds) ? new Set(meta.allowedTransportIds) : null;",
    "const allowedIds = new Set(['wifi']); // Wi-Fi-only build policy; adapter contract stays extensible.",
    "core allowed transport policy",
)
replace_once(
    core_js,
    "{ id: 'meshtastic', name: 'Meshtastic', available: true,",
    "{ id: 'meshtastic', name: 'Meshtastic', available: false,",
    "disable default Meshtastic availability",
)

# Fast-route policy: LAN only; Internet relay remains dormant source for future expansion.
regex_once(
    app_js,
    r"function pickFastRoute\(peerId\) \{.*?\n\}\n\nfunction flushFastQueuedMessages",
    """function pickFastRoute(peerId) {
  const lanReady = Boolean(lanTransport?.isReady?.()) && (!lanPeer?.peerId || lanPeer.peerId === peerId);
  if (lanReady) return 'wifi';
  return null;
}

function flushFastQueuedMessages""",
    "LAN-only fast route",
    flags=re.DOTALL,
)
replace_once(
    app_js,
    "const peers = new Set([lanPeer?.peerId, internetPeer?.peerId].filter(Boolean));",
    "const peers = new Set([lanPeer?.peerId].filter(Boolean));",
    "LAN-only queued peer set",
)
replace_once(
    app_js,
    "message.transport = route === 'wifi' ? 'Wi‑Fi LAN' : 'Internet relay';",
    "message.transport = 'Wi‑Fi LAN';",
    "LAN-only queued transport label",
)
regex_once(
    app_js,
    r"(function renderConnection\(\) \{\s*\n\s*)const items = transportManager\.list\(\);",
    r"\1const items = transportManager.list().filter(t => t.id === 'wifi');",
    "show only Wi-Fi transport row",
)
app_text = read(app_js)
app_text = app_text.replace(
    "internetRelayTransport?.setIdentity?.({ peerId: appPeerId, displayName: appDisplayName });\n",
    "",
)
old_send_guard = """  if ((lanPeer?.peerId === chat.id) || (internetPeer?.peerId === chat.id) || chat.transport === 'Wi‑Fi LAN' || chat.transport === 'Internet') {
    return sendFastText(chat, cleanText);
  }
"""
new_send_guard = """  if ((lanPeer?.peerId === chat.id) || chat.transport === 'Wi‑Fi LAN') {
    return sendFastText(chat, cleanText);
  }
  openLanPairing();
  return;
"""
if old_send_guard not in app_text:
    raise SystemExit("sendMessage Wi-Fi-only guard: source pattern not found")
app_text = app_text.replace(old_send_guard, new_send_guard, 1)
old_fast_msg = "transport: route === 'wifi' ? 'Wi‑Fi LAN' : route === 'ip' ? 'Internet relay' : 'Авто'"
if old_fast_msg not in app_text:
    raise SystemExit("sendFastText transport label: source pattern not found")
app_text = app_text.replace(old_fast_msg, "transport: 'Wi‑Fi LAN'", 1)
if "Web/PWA v1.6.0-alpha1" not in app_text:
    raise SystemExit("runtime version marker not found")
app_text = app_text.replace("Web/PWA v1.6.0-alpha1", "Web/PWA v1.6.0-alpha2", 1)
write(app_js, app_text)

# Remove Internet relay UI from this build. The transport source can be re-enabled later.
itext = read(index_html)
itext, removed = re.subn(
    r'\n\s*<section class="modal-layer" id="internetRelayModal".*?</section>\s*\n',
    '\n',
    itext,
    count=1,
    flags=re.DOTALL,
)
if removed != 1:
    raise SystemExit(f"internet relay modal: expected 1 section, got {removed}")
write(index_html, itext)

# Keep Help focused on capabilities that are actually exposed in this build.
htext = read(help_js)
for topic in ("mesh-messenger.network.internet", "mesh-messenger.network.bluetooth"):
    before = htext
    htext = "\n".join(line for line in htext.splitlines() if topic not in line) + "\n"
    if htext == before:
        raise SystemExit(f"help topic not found: {topic}")
write(help_js, htext)

# Hide legacy radio/BLE panel while preserving code for future adapter reactivation.
stext = read(styles)
stext += """
/* v1.6.0-alpha2 Wi-Fi-only product policy */
.radio-link-card{display:none!important}
"""
write(styles, stext)

# Do not precache the dormant relay module.
sw_text = read(sw)
sw_text = sw_text.replace("  './src/transports/internet-relay-transport.js',\n", "")
sw_text = sw_text.replace("mesh-messenger-v160-alpha1", "mesh-wifi-v160-alpha2")
write(sw, sw_text)

# Final deterministic guardrails.
checks = {
    "version alpha2": 'versionName = "1.6.0-alpha2"' in read(build),
    "versionCode 23": "versionCode = 23" in read(build),
    "LAN transport source": (www / "src" / "transports" / "lan-peer-transport.js").is_file(),
    "internet modal absent": 'id="internetRelayModal"' not in read(index_html),
    "internet help absent": "mesh-messenger.network.internet" not in read(help_js),
    "bluetooth permission absent": "BLUETOOTH_SCAN" not in read(manifest) and "BLUETOOTH_CONNECT" not in read(manifest),
    "Wi-Fi-only selector": "new Set(['wifi'])" in read(core_js),
    "Wi-Fi-only transport list": "transportManager.list().filter(t => t.id === 'wifi')" in read(app_js),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("wifi-only overlay checks failed: " + ", ".join(failed))

print("WIFI_ONLY_OVERLAY_PASS")
