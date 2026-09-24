from pathlib import Path

ROOT = Path("upstream")
html_path = ROOT / "app/src/main/assets/flash.html"
bridge_path = ROOT / "app/src/main/java/io/github/drakosha/espflash/JsBridge.kt"
usb_path = ROOT / "app/src/main/java/io/github/drakosha/espflash/UsbSerialManager.kt"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


# ---- flash.html -------------------------------------------------------------
html = html_path.read_text(encoding="utf-8")

html = html.replace("<title>ESP Flash</title>", "<title>ESP Service Studio</title>")
html = replace_once(
    html,
    "  label.field { display: block; font-size: 12px; color: #888; margin-bottom: 6px; }\n",
    "  label.field { display: block; font-size: 12px; color: #888; margin-bottom: 6px; }\n"
    "  .manual-mode { display: flex; gap: 10px; align-items: center; margin: -4px 0 16px;\n"
    "                 padding: 10px 12px; border-radius: 7px; background: #1e1e1e; color: #ddd;\n"
    "                 font-size: 13px; }\n"
    "  .manual-mode input { width: 20px; height: 20px; accent-color: #2196f3; }\n",
    "manual CSS",
)

html = replace_once(
    html,
    "  <select id=\"preset\"></select>\n  <div id=\"parts\"></div>\n",
    "  <select id=\"preset\"></select>\n"
    "  <label class=\"manual-mode\"><input type=\"checkbox\" id=\"manualBoot\" checked>"
    "<span id=\"manualBootLabel\"></span></label>\n"
    "  <div id=\"parts\"></div>\n",
    "manual checkbox",
)

html = replace_once(
    html,
    "    instructions: '<b>1.</b> Connect the board to the phone via USB OTG<br>' +\n"
    "                  '<b>2.</b> Hold BOOT, tap RESET, release BOOT<br>' +\n"
    "                  '<b>3.</b> Pick the binaries and tap Flash',\n",
    "    instructions: '<b>1.</b> For one-button boards hold BOOT while connecting USB/power<br>' +\n"
    "                  '<b>2.</b> Release BOOT after the board powers up<br>' +\n"
    "                  '<b>3.</b> Pick the binaries and tap Flash',\n"
    "    manualBootLabel: 'One-button manual BOOT (no RESET, no stub)',\n"
    "    manualBootActive: 'Manual BOOT mode: ROM flashing, no stub and no automatic reset.',\n"
    "    eraseManualDisabled: 'Whole-flash erase needs the stub. Turn off manual BOOT mode only if your board supports automatic reset.',\n",
    "english instructions",
)
html = replace_once(
    html,
    "    instructionsEmbedded: '<b>1.</b> Connect the board to the phone via USB OTG<br>' +\n"
    "                          '<b>2.</b> Hold BOOT, tap RESET, release BOOT<br>' +\n"
    "                          '<b>3.</b> Tap Flash',\n",
    "    instructionsEmbedded: '<b>1.</b> Hold BOOT while connecting USB/power<br>' +\n"
    "                          '<b>2.</b> Release BOOT after power-up<br>' +\n"
    "                          '<b>3.</b> Tap Flash',\n",
    "english embedded instructions",
)
html = replace_once(
    html,
    "    bootHint: 'Hold BOOT, tap RESET, release BOOT and try again.',\n",
    "    bootHint: 'One-button board: disconnect USB, hold BOOT, reconnect USB/power, release BOOT, then try again.',\n",
    "english boot hint",
)

html = replace_once(
    html,
    "    instructions: '<b>1.</b> Подключите плату к телефону по USB OTG<br>' +\n"
    "                  '<b>2.</b> Зажмите BOOT, нажмите RESET, отпустите BOOT<br>' +\n"
    "                  '<b>3.</b> Выберите файлы и нажмите «Прошить»',\n",
    "    instructions: '<b>1.</b> На плате с одной кнопкой зажмите BOOT и подключите USB/питание<br>' +\n"
    "                  '<b>2.</b> После включения отпустите BOOT<br>' +\n"
    "                  '<b>3.</b> Выберите файлы и нажмите «Прошить»',\n"
    "    manualBootLabel: 'Одна кнопка: ручной BOOT (без RESET и без stub)',\n"
    "    manualBootActive: 'Ручной BOOT: прошивка напрямую через ROM, без stub и автосброса.',\n"
    "    eraseManualDisabled: 'Полное стирание требует stub. Отключайте ручной BOOT только если плата поддерживает автоматический сброс.',\n",
    "russian instructions",
)
html = replace_once(
    html,
    "    instructionsEmbedded: '<b>1.</b> Подключите плату к телефону по USB OTG<br>' +\n"
    "                          '<b>2.</b> Зажмите BOOT, нажмите RESET, отпустите BOOT<br>' +\n"
    "                          '<b>3.</b> Нажмите «Прошить»',\n",
    "    instructionsEmbedded: '<b>1.</b> Зажмите BOOT и подключите USB/питание<br>' +\n"
    "                          '<b>2.</b> После включения отпустите BOOT<br>' +\n"
    "                          '<b>3.</b> Нажмите «Прошить»',\n",
    "russian embedded instructions",
)
html = replace_once(
    html,
    "    bootHint: 'Зажмите BOOT, нажмите RESET, отпустите BOOT и повторите.',\n",
    "    bootHint: 'Плата с одной кнопкой: отключите USB, зажмите BOOT, подключите USB/питание, отпустите BOOT и повторите.',\n",
    "russian boot hint",
)

html = replace_once(
    html,
    "  getInfo() { return { usbVendorId: 0x303A, usbProductId: 0x1001 }; }\n",
    "  getInfo() {\n"
    "    return { usbVendorId: Android.usbVendorId(), usbProductId: Android.usbProductId() };\n"
    "  }\n",
    "real USB VID/PID",
)

html = replace_once(
    html,
    "async function connectLoader(mode, attempts) {\n",
    "async function connectLoader(mode, attempts, useStub = false) {\n",
    "connectLoader signature",
)
html = replace_once(
    html,
    "    if (loader.chip.postConnect) await loader.chip.postConnect(loader);\n    await loader.runStub();\n    return { loader, serialPort, chip };\n",
    "    if (loader.chip.postConnect) await loader.chip.postConnect(loader);\n"
    "    if (useStub) {\n"
    "      await loader.runStub();\n"
    "    } else {\n"
    "      // ROM bootloaders use 0x400-byte flash blocks. ESPLoader defaults to\n"
    "      // 0x4000, which is correct only for the uploaded flasher stub. v0.2\n"
    "      // disabled runStub() but accidentally kept the stub-sized blocks.\n"
    "      loader.FLASH_WRITE_SIZE = (loader.chip && loader.chip.FLASH_WRITE_SIZE) || 0x400;\n"
    "      log('ROM flash block: ' + loader.FLASH_WRITE_SIZE + ' B', 'info');\n"
    "    }\n"
    "    return { loader, serialPort, chip };\n",
    "ROM-safe flash block",
)

old_open = """async function openChip() {
  try {
    return await connectLoader('no_reset', 2);
  } catch (e) {
    log(t().resetFailed(e.message), 'err');
    log(t().retryWithReset, 'info');
    try { Android.disconnect(); } catch(_) {}
    await new Promise(r => setTimeout(r, 800));
    return await connectLoader('default_reset', 3);
  }
}
"""
new_open = """async function openChip(useStub = false) {
  const manualBoot = document.getElementById('manualBoot')?.checked !== false;
  if (manualBoot) {
    log(t().manualBootActive, 'info');
    // One-button boards are already in the ROM downloader after power-up with
    // BOOT held. Do not toggle DTR/RTS and, for normal flashing, do not upload
    // the flasher stub: the user's CH340 link was dropping exactly at runStub().
    return await connectLoader('no_reset', 3, useStub);
  }
  try {
    return await connectLoader('no_reset', 2, useStub);
  } catch (e) {
    log(t().resetFailed(e.message), 'err');
    log(t().retryWithReset, 'info');
    try { Android.disconnect(); } catch(_) {}
    await new Promise(r => setTimeout(r, 800));
    return await connectLoader('default_reset', 3, useStub);
  }
}
"""
html = replace_once(html, old_open, new_open, "manual openChip")

html = replace_once(
    html,
    "    session = await openChip();\n    log(t().chip(session.chip), 'ok');\n\n    const fileArray = loadParts();\n",
    "    session = await openChip(false);\n    log(t().chip(session.chip), 'ok');\n\n    const fileArray = loadParts();\n",
    "flash without stub",
)

html = replace_once(
    html,
    "async function doErase() {\n  if (!confirm(t().eraseConfirm)) return;\n",
    "async function doErase() {\n"
    "  if (document.getElementById('manualBoot')?.checked) {\n"
    "    openLog();\n"
    "    log(t().eraseManualDisabled, 'err');\n"
    "    return;\n"
    "  }\n"
    "  if (!confirm(t().eraseConfirm)) return;\n",
    "manual erase guard",
)
html = replace_once(
    html,
    "    session = await openChip();\n    log(t().chip(session.chip), 'ok');\n    await session.loader.eraseFlash();\n",
    "    session = await openChip(true);\n    log(t().chip(session.chip), 'ok');\n    await session.loader.eraseFlash();\n",
    "erase with stub",
)

html = replace_once(
    html,
    "    (embedded && embedded.name) ? embedded.name : 'ESP Flash';\n",
    "    (embedded && embedded.name) ? embedded.name : 'ESP Service Studio';\n",
    "app title",
)
html = replace_once(
    html,
    "  document.getElementById('presetLabel').textContent = T.presetLabel;\n",
    "  document.getElementById('presetLabel').textContent = T.presetLabel;\n"
    "  document.getElementById('manualBootLabel').textContent = T.manualBootLabel;\n",
    "manual label language",
)

# Keep the erase button disabled in manual ROM mode. Flash remains available.
html = replace_once(
    html,
    "    flash.disabled = false;\n    erase.disabled = false;\n",
    "    flash.disabled = false;\n    erase.disabled = document.getElementById('manualBoot')?.checked !== false;\n",
    "erase connected state",
)

html = replace_once(
    html,
    "document.getElementById('addPart').addEventListener('click', () => {\n",
    "document.getElementById('manualBoot').addEventListener('change', () => {\n"
    "  const connected = document.getElementById('usbDot').className.includes('connected');\n"
    "  document.getElementById('eraseBtn').disabled = connected && document.getElementById('manualBoot').checked;\n"
    "});\n"
    "document.getElementById('addPart').addEventListener('click', () => {\n",
    "manual checkbox listener",
)

# v0.3: when flashing directly through ROM (manual BOOT, no stub), use the
# chip ROM block size (normally 0x400 = 1024 B). Also do not send FLASH_END
# after a normal ROM write; esptool-js 0.6.1 only does that for the stub.
html = replace_once(
    html,
    "  const BS = loader.FLASH_WRITE_SIZE;  // 16384 со стабом\n",
    "  const BS = loader.IS_STUB ? loader.FLASH_WRITE_SIZE\n"
    "                            : ((loader.chip && loader.chip.FLASH_WRITE_SIZE) || 0x400);\n"
    "  loader.FLASH_WRITE_SIZE = BS;\n",
    "ROM write block size",
)
html = replace_once(
    html,
    "  await loader.flashFinish(false);\n}\n",
    "  if (loader.IS_STUB) await loader.flashFinish(false);\n}\n",
    "ROM flash finish",
)

html_path.write_text(html, encoding="utf-8")

# ---- JsBridge.kt: expose the actual selected USB IDs to esptool-js ----------
bridge = bridge_path.read_text(encoding="utf-8")
bridge = replace_once(
    bridge,
    "    @JavascriptInterface\n    fun deviceInfo(): String {\n        val device = usbManager.findDevice() ?: return \"\"\n        return usbManager.describeDevice(device)\n    }\n\n",
    "    @JavascriptInterface\n"
    "    fun deviceInfo(): String {\n"
    "        val device = usbManager.findDevice() ?: return \"\"\n"
    "        return usbManager.describeDevice(device)\n"
    "    }\n\n"
    "    @JavascriptInterface\n"
    "    fun usbVendorId(): Int = usbManager.currentVendorId()\n\n"
    "    @JavascriptInterface\n"
    "    fun usbProductId(): Int = usbManager.currentProductId()\n\n",
    "USB ID bridge",
)
bridge_path.write_text(bridge, encoding="utf-8")

# ---- UsbSerialManager.kt: pin the device chosen by status/checkConnection ----
usb = usb_path.read_text(encoding="utf-8")
usb = replace_once(
    usb,
    "    private var port: UsbSerialPort? = null\n    private var readThread: Thread? = null\n",
    "    private var port: UsbSerialPort? = null\n"
    "    private var readThread: Thread? = null\n"
    "    private var selectedDeviceName: String? = null\n"
    "    private var selectedVendorId: Int = 0\n"
    "    private var selectedProductId: Int = 0\n",
    "selected USB state",
)
old_find = """    /** Первое подключённое устройство, для которого есть serial-драйвер. */
    fun findDevice(): UsbDevice? {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val prober = UsbSerialProber.getDefaultProber()
        return usbManager.deviceList.values.find { prober.probeDevice(it) != null }
    }
"""
new_find = """    /**
     * Keep using the same Android USB device throughout one operation. The old
     * implementation asked deviceList for the 'first' serial device every time;
     * its map order is not a device-selection contract and could change between
     * checkConnection(), deviceInfo() and connect().
     */
    fun findDevice(): UsbDevice? {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val prober = UsbSerialProber.getDefaultProber()
        val devices = usbManager.deviceList.values.filter { prober.probeDevice(it) != null }
        val pinned = selectedDeviceName?.let { name -> devices.firstOrNull { it.deviceName == name } }
        val chosen = pinned ?: devices.firstOrNull()
        if (chosen != null) {
            selectedDeviceName = chosen.deviceName
            selectedVendorId = chosen.vendorId
            selectedProductId = chosen.productId
        }
        return chosen
    }

    fun currentVendorId(): Int {
        findDevice()
        return selectedVendorId
    }

    fun currentProductId(): Int {
        findDevice()
        return selectedProductId
    }
"""
usb = replace_once(usb, old_find, new_find, "pinned USB device")
usb_path.write_text(usb, encoding="utf-8")

# CI sanity checks: fail the build rather than silently ship an unpatched APK.
patched = html_path.read_text(encoding="utf-8")
checks = [
    "One-button manual BOOT",
    "Одна кнопка: ручной BOOT",
    "Android.usbVendorId()",
    "connectLoader('no_reset', 3, useStub)",
    "session = await openChip(false)",
    "loader.FLASH_WRITE_SIZE = (loader.chip && loader.chip.FLASH_WRITE_SIZE) || 0x400",
    "if (loader.IS_STUB) await loader.flashFinish(false)",
]
for needle in checks:
    if needle not in patched:
        raise SystemExit(f"missing patched marker: {needle}")
if "getInfo() { return { usbVendorId: 0x303A" in patched:
    raise SystemExit("hard-coded USB IDs survived patch")

print("ESP Service Studio Android v0.3 patch applied successfully")
