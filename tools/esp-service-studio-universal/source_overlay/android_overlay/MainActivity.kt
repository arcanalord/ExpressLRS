package com.arcanalord.service_studio

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val ACTION_USB_PERMISSION =
            "com.arcanalord.service_studio.USB_PERMISSION"
        private const val REQUEST_PICK_MESH_FIRMWARE = 42017
        private const val MESH_EP2_V040_SHA256 =
            "6358bdaf6d6dd5edee3ef3e3f1f648bcec445ce80599017a172e2acfd97adadb"
        private const val MESH_EP2_V043_SHA256 =
            "c59351a70d06fd6db8c1a8b16d6c2e93325225bbd3f64c3725f5dbcfeafbe50b"
        private const val MESH_EP2_ELRS_TARGET = "Unified_ESP8285_2400_RX"
    }

    private val methodChannelName = "service_studio/native"
    private val eventChannelName = "service_studio/usb_events"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var usbEventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private var pendingProbeResult: MethodChannel.Result? = null
    private var pendingProbeDeviceName: String? = null
    private var pendingMeshPickResult: MethodChannel.Result? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return

            when (action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    emitUsbSnapshot("attached", 80)
                }

                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    emitUsbSnapshot("detached", 180)
                }

                ACTION_USB_PERMISSION -> {
                    val granted = intent.getBooleanExtra(
                        UsbManager.EXTRA_PERMISSION_GRANTED,
                        false,
                    )
                    val device = usbDeviceFromIntent(intent)
                    completePermissionProbe(granted, device)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleUsbIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleUsbIntent(intent)
    }

    @Deprecated("Deprecated in Android API; retained for document picker compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_MESH_FIRMWARE) return

        val result = pendingMeshPickResult ?: return
        pendingMeshPickResult = null

        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(
                mapOf(
                    "status" to "cancelled",
                    "message" to "Выбор Mesh прошивки отменён",
                ),
            )
            return
        }

        val uri = data.data!!
        Thread {
            val response = prepareKnownMeshFirmware(uri)
            mainHandler.post { result.success(response) }
        }.start()
    }

    private fun containsSequence(haystack: ByteArray, needle: ByteArray): Boolean {
        if (needle.isEmpty() || haystack.size < needle.size) return false
        outer@ for (i in 0..haystack.size - needle.size) {
            for (j in needle.indices) {
                if (haystack[i + j] != needle[j]) continue@outer
            }
            return true
        }
        return false
    }

    private fun prepareKnownMeshFirmware(uri: android.net.Uri): Map<String, Any?> {
        return try {
            val displayName = runCatching {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { cursor ->
                        if (cursor.moveToFirst()) cursor.getString(0) else null
                    }
            }.getOrNull()

            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: error("Не удалось прочитать выбранный файл")

            if (bytes.size !in 64_000..1_048_576) {
                error("Размер Mesh прошивки выглядит неверно: ${bytes.size} Б")
            }

            val sha = MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") { "%02x".format(it) }

            val meshVersion = when {
                sha.equals(MESH_EP2_V043_SHA256, ignoreCase = true) -> "v0.4.3-dev"
                sha.equals(MESH_EP2_V040_SHA256, ignoreCase = true) -> "v0.4.0"
                else -> error(
                    "Файл не входит в разрешённый каталог Mesh Messenger EP2. " +
                        "SHA-256: $sha"
                )
            }
            val candidate = meshVersion == "v0.4.3-dev"
            if (candidate) {
                val marker = ("\u00BE\u00EF\u00CA\u00FE" + MESH_EP2_ELRS_TARGET)
                    .toByteArray(Charsets.ISO_8859_1)
                if (!containsSequence(bytes, marker)) {
                    error(
                        "v0.4.3-dev не содержит обязательный ExpressLRS target marker " +
                            MESH_EP2_ELRS_TARGET
                    )
                }
            }

            val dir = File(filesDir, "firmware/mesh/happymodel_ep2/$meshVersion")
            if (!dir.exists() && !dir.mkdirs()) {
                error("Не удалось создать каталог Mesh прошивки")
            }

            val firmware = File(dir, "firmware.bin")
            firmware.writeBytes(bytes)

            val manifest = org.json.JSONObject()
                .put("kind", "mesh")
                .put("version", meshVersion)
                .put("targetPath", "mesh.happymodel_ep2")
                .put("productName", "Mesh Messenger / HappyModel EP2")
                .put("platform", "esp8285")
                .put("firmware", "MeshMessenger_EP2")
                .put("boardId", "happymodel_ep2")
                .put(
                    "hardwareSource",
                    if (candidate) "mesh-candidate-pinned" else "mesh-release-pinned",
                )
                .put("wifiFirstFlashCompatible", candidate)
                .put("expressLrsTarget", if (candidate) MESH_EP2_ELRS_TARGET else org.json.JSONObject.NULL)
                .put("writeOffset", "0x0")
                .put("fileName", firmware.name)
                .put("fileSize", firmware.length())
                .put("sha256", sha)
                .put("hardwarePinned", true)

            val manifestFile = File(dir, "manifest.json")
            manifestFile.writeText(manifest.toString(2), Charsets.UTF_8)

            mapOf(
                "status" to "prepared",
                "message" to "Mesh Messenger EP2 $meshVersion проверена и готова к ROM-записи",
                "version" to meshVersion,
                "targetPath" to "mesh.happymodel_ep2",
                "productName" to "Mesh Messenger / HappyModel EP2",
                "platform" to "esp8285",
                "firmware" to "MeshMessenger_EP2",
                "boardId" to "happymodel_ep2",
                "writeOffset" to "0x0",
                "filePath" to firmware.absolutePath,
                "fileSize" to firmware.length(),
                "sha256" to sha,
                "manifestPath" to manifestFile.absolutePath,
                "sourceFileName" to displayName,
                "hardwareSource" to
                    if (candidate) "mesh-candidate-pinned" else "mesh-release-pinned",
                "hardwarePinned" to true,
                "wifiFirstFlashCompatible" to candidate,
                "expressLrsTarget" to if (candidate) MESH_EP2_ELRS_TARGET else null,
                "readyToFlash" to true,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Mesh прошивка отклонена: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        registerUsbReceiver()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listUsbDevices" -> result.success(listUsbDevices())

                    "platformInfo" -> result.success(
                        "${Build.MANUFACTURER} ${Build.MODEL}; Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
                    )

                    "probeEspRom" -> {
                        val deviceName = call.argument<String>("deviceName")
                        startEspProbe(deviceName, result)
                    }

                    "pickKnownMeshFirmware" -> {
                        if (pendingMeshPickResult != null) {
                            result.error("BUSY", "Выбор прошивки уже открыт", null)
                        } else {
                            pendingMeshPickResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/octet-stream"
                                putExtra(
                                    Intent.EXTRA_MIME_TYPES,
                                    arrayOf(
                                        "application/octet-stream",
                                        "application/macbinary",
                                        "*/*",
                                    ),
                                )
                            }
                            startActivityForResult(intent, REQUEST_PICK_MESH_FIRMWARE)
                        }
                    }

                    "meshServiceCommand" -> {
                        val deviceName = call.argument<String>("deviceName")
                        val command = call.argument<Int>("command") ?: 0x16
                        Thread {
                            val probe = UsbSerialProbe(this)
                            val device = probe.findDevice(deviceName)
                            val response = if (device == null) {
                                mapOf(
                                    "status" to "mesh_no_device",
                                    "message" to "USB-UART не найден",
                                )
                            } else {
                                probe.meshServiceCommand(device, command)
                            }
                            mainHandler.post {
                                result.success(response)
                                emitUsbSnapshot("mesh_service", 0)
                            }
                        }.start()
                    }


                    "fetchOfficialElrsCatalogIndex" -> {
                        Thread {
                            val response = OfficialElrsService(this).fetchCatalogIndex()
                            mainHandler.post { result.success(response) }
                        }.start()
                    }

                    "fetchOfficialElrsTarget" -> {
                        val targetPath = call.argument<String>("targetPath") ?: ""
                        val expectedProductName =
                            call.argument<String>("expectedProductName") ?: ""
                        val expectedPlatform =
                            call.argument<String>("expectedPlatform") ?: ""
                        val expectedFirmware =
                            call.argument<String>("expectedFirmware") ?: ""
                        val expectedCommitSha =
                            call.argument<String>("expectedCommitSha") ?: ""
                        Thread {
                            val response = OfficialElrsService(this).fetchCatalog(
                                targetPath = targetPath,
                                expectedProductName = expectedProductName,
                                expectedPlatform = expectedPlatform,
                                expectedFirmware = expectedFirmware,
                                expectedCommitSha = expectedCommitSha,
                            )
                            mainHandler.post { result.success(response) }
                        }.start()
                    }

                    "flashPreparedEsp8285" -> {
                        val deviceName = call.argument<String>("deviceName")
                        val manifestPath = call.argument<String>("manifestPath") ?: ""
                        val expectedTargetPath =
                            call.argument<String>("expectedTargetPath") ?: ""
                        val expectedSha256 =
                            call.argument<String>("expectedSha256") ?: ""

                        Thread {
                            val probe = UsbSerialProbe(this)
                            val device = probe.findDevice(deviceName)
                            val response = if (device == null) {
                                mapOf(
                                    "status" to "flash_error",
                                    "message" to "USB-UART не найден",
                                )
                            } else {
                                probe.flashPrepared(
                                    device = device,
                                    manifestPath = manifestPath,
                                    expectedTargetPath = expectedTargetPath,
                                    expectedSha256 = expectedSha256,
                                )
                            }
                            mainHandler.post {
                                result.success(response)
                                emitUsbSnapshot("flash_complete", 0)
                            }
                        }.start()
                    }

                    "prepareOfficialElrsTarget" -> {
                        val targetPath = call.argument<String>("targetPath") ?: ""
                        val expectedProductName =
                            call.argument<String>("expectedProductName") ?: ""
                        val expectedPlatform =
                            call.argument<String>("expectedPlatform") ?: ""
                        val expectedFirmware =
                            call.argument<String>("expectedFirmware") ?: ""
                        val expectedCommitSha =
                            call.argument<String>("expectedCommitSha") ?: ""
                        val regulatoryDomain =
                            call.argument<String>("regulatoryDomain") ?: ""
                        val bindingPhrase = call.argument<String>("bindingPhrase")
                        val wifiSsid = call.argument<String>("wifiSsid")
                        val wifiPassword = call.argument<String>("wifiPassword")
                        val autoWifiSeconds = call.argument<Int>("autoWifiSeconds")
                        val rxUartBaud = call.argument<Int>("rxUartBaud")
                        val lockOnFirstConnection =
                            call.argument<Boolean>("lockOnFirstConnection")
                        Thread {
                            val response = OfficialElrsService(this).prepareFirmware(
                                targetPath = targetPath,
                                expectedProductName = expectedProductName,
                                expectedPlatform = expectedPlatform,
                                expectedFirmware = expectedFirmware,
                                expectedCommitSha = expectedCommitSha,
                                regulatoryDomain = regulatoryDomain,
                                bindingPhrase = bindingPhrase,
                                wifiSsid = wifiSsid,
                                wifiPassword = wifiPassword,
                                autoWifiSeconds = autoWifiSeconds,
                                lockOnFirstConnection = lockOnFirstConnection,
                                rxUartBaud = rxUartBaud,
                            )
                            mainHandler.post { result.success(response) }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    usbEventSink = events
                    emitUsbSnapshot("snapshot", 0)
                }

                override fun onCancel(arguments: Any?) {
                    usbEventSink = null
                }
            })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingProbeResult?.error(
            "ACTIVITY_DESTROYED",
            "Проверка USB прервана",
            null,
        )
        pendingProbeResult = null
        pendingProbeDeviceName = null
        usbEventSink = null
        unregisterUsbReceiver()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleUsbIntent(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            emitUsbSnapshot("attached_intent", 120)
        }
    }

    private fun startEspProbe(
        requestedDeviceName: String?,
        result: MethodChannel.Result,
    ) {
        if (pendingProbeResult != null) {
            result.error("BUSY", "Проверка USB уже выполняется", null)
            return
        }

        val probe = UsbSerialProbe(this)
        val device = probe.findDevice(requestedDeviceName)

        if (device == null) {
            result.success(
                mapOf(
                    "status" to "no_device",
                    "message" to "USB-устройство не найдено",
                )
            )
            return
        }

        if (probe.hasPermission(device)) {
            runProbeAsync(device, result)
            return
        }

        pendingProbeResult = result
        pendingProbeDeviceName = device.deviceName

        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        val permissionIntent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(ACTION_USB_PERMISSION).setPackage(packageName),
            flags,
        )

        try {
            manager.requestPermission(device, permissionIntent)
        } catch (e: Exception) {
            pendingProbeResult = null
            pendingProbeDeviceName = null
            result.success(
                mapOf(
                    "status" to "permission_error",
                    "message" to "Не удалось запросить доступ к USB: ${e.message ?: e.javaClass.simpleName}",
                )
            )
        }
    }

    private fun completePermissionProbe(
        granted: Boolean,
        deviceFromIntent: UsbDevice?,
    ) {
        val result = pendingProbeResult ?: return
        val requestedName = pendingProbeDeviceName

        pendingProbeResult = null
        pendingProbeDeviceName = null

        if (!granted) {
            result.success(
                mapOf(
                    "status" to "permission_denied",
                    "message" to "Доступ Android к USB отклонён",
                )
            )
            return
        }

        val probe = UsbSerialProbe(this)
        val device = deviceFromIntent ?: probe.findDevice(requestedName)

        if (device == null) {
            result.success(
                mapOf(
                    "status" to "no_device",
                    "message" to "USB-устройство отключено до начала проверки",
                )
            )
            return
        }

        runProbeAsync(device, result)
    }

    private fun runProbeAsync(
        device: UsbDevice,
        result: MethodChannel.Result,
    ) {
        Thread {
            val probeResult = UsbSerialProbe(this).probe(device)
            mainHandler.post {
                result.success(probeResult)
                emitUsbSnapshot("probe_complete", 0)
            }
        }.start()
    }

    private fun usbDeviceFromIntent(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(
                UsbManager.EXTRA_DEVICE,
                UsbDevice::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }

    private fun emitUsbSnapshot(event: String, delayMs: Long) {
        mainHandler.postDelayed({
            usbEventSink?.success(
                mapOf(
                    "event" to event,
                    "devices" to listUsbDevices(),
                )
            )
        }, delayMs)
    }

    private fun registerUsbReceiver() {
        if (receiverRegistered) return

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_USB_PERMISSION)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                usbReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(usbReceiver, filter)
        }

        receiverRegistered = true
    }

    private fun unregisterUsbReceiver() {
        if (!receiverRegistered) return
        runCatching { unregisterReceiver(usbReceiver) }
        receiverRegistered = false
    }

    private fun listUsbDevices(): List<Map<String, Any?>> {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager

        return manager.deviceList.values.map { device ->
            mapOf(
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "deviceName" to device.deviceName,
                "interfaceCount" to device.interfaceCount,
                "manufacturer" to runCatching {
                    device.manufacturerName
                }.getOrNull(),
                "product" to runCatching {
                    device.productName
                }.getOrNull(),
                "hasPermission" to manager.hasPermission(device),
            )
        }.sortedWith(
            compareBy(
                { it["vendorId"] as Int },
                { it["productId"] as Int },
            )
        )
    }
}
