package com.arcanalord.service_studio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "service_studio/native"
    private val eventChannelName = "service_studio/usb_events"

    private var usbEventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            if (action != UsbManager.ACTION_USB_DEVICE_ATTACHED &&
                action != UsbManager.ACTION_USB_DEVICE_DETACHED
            ) {
                return
            }

            usbEventSink?.success(
                mapOf(
                    "event" to if (action == UsbManager.ACTION_USB_DEVICE_ATTACHED) "attached" else "detached",
                    "devices" to listUsbDevices(),
                )
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listUsbDevices" -> result.success(listUsbDevices())
                    "platformInfo" -> result.success(
                        "${Build.MANUFACTURER} ${Build.MODEL}; Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
                    )
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    usbEventSink = events
                    registerUsbReceiver()
                    events?.success(
                        mapOf(
                            "event" to "snapshot",
                            "devices" to listUsbDevices(),
                        )
                    )
                }

                override fun onCancel(arguments: Any?) {
                    usbEventSink = null
                    unregisterUsbReceiver()
                }
            })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        usbEventSink = null
        unregisterUsbReceiver()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun registerUsbReceiver() {
        if (receiverRegistered) return

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
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
                "manufacturer" to runCatching { device.manufacturerName }.getOrNull(),
                "product" to runCatching { device.productName }.getOrNull(),
            )
        }.sortedWith(compareBy({ it["vendorId"] as Int }, { it["productId"] as Int }))
    }
}
