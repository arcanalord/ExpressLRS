package com.arcanalord.service_studio

import android.content.Context
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "service_studio/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listUsbDevices" -> result.success(listUsbDevices())
                    "platformInfo" -> result.success(
                        "${Build.MANUFACTURER} ${Build.MODEL}; Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
                    )
                    else -> result.notImplemented()
                }
            }
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
