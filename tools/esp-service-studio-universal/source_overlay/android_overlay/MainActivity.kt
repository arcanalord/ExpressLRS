package com.arcanalord.service_studio

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val ACTION_USB_PERMISSION =
            "com.arcanalord.service_studio.USB_PERMISSION"
    }

    private val methodChannelName = "service_studio/native"
    private val eventChannelName = "service_studio/usb_events"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var usbEventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private var pendingProbeResult: MethodChannel.Result? = null
    private var pendingProbeDeviceName: String? = null

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
                        Thread {
                            val response = OfficialElrsService(this).fetchCatalog(
                                targetPath = targetPath,
                                expectedProductName = expectedProductName,
                                expectedPlatform = expectedPlatform,
                                expectedFirmware = expectedFirmware,
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
