package org.fpvclub.mesh

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val secureIdentity: SecureIdentityStore by lazy { SecureIdentityStore(applicationContext) }
    private val main = Handler(Looper.getMainLooper())
    private val ble: MeshtasticBleClient by lazy {
        MeshtasticBleClient(applicationContext).also { client ->
            client.onState = { state, error ->
                main.post {
                    meshtasticEventSink?.success(
                        mapOf("type" to "state", "state" to state, "error" to error),
                    )
                }
            }
            client.onLog = { message ->
                main.post {
                    meshtasticEventSink?.success(
                        mapOf(
                            "type" to "log",
                            "message" to message,
                            "at" to System.currentTimeMillis(),
                        ),
                    )
                }
            }
            client.onFromRadio = { bytes ->
                main.post {
                    meshtasticEventSink?.success(mapOf("type" to "fromRadio", "bytes" to bytes))
                }
            }
        }
    }

    private var meshtasticEventSink: EventChannel.EventSink? = null
    private var usbEventSink: EventChannel.EventSink? = null
    private var usbDetach: (() -> Unit)? = null
    private var permissionResult: MethodChannel.Result? = null
    private var localNetworkPermissionResult: MethodChannel.Result? = null
    private val permissionRequestCode = 1501
    private val localNetworkPermissionRequestCode = 1502
    private val localNetworkPermission = "android.permission.ACCESS_LOCAL_NETWORK"
    private val mapPackageStore: MapPackageStore by lazy { MapPackageStore(applicationContext) }
    private var mapImportResult: MethodChannel.Result? = null
    private val mapImportRequestCode = 1601

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UsbSerialRuntime.initialize(applicationContext)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "org.fpvclub.mesh/mapview",
            MapPlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger, mapPackageStore),
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/maps",
        ).setMethodCallHandler(::handleMapMethod)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/localnetwork",
        ).setMethodCallHandler(::handleLocalNetworkMethod)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/secureidentity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadOrCreate" -> runAsync(result) { secureIdentity.loadOrCreate() }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/meshtastic",
        ).setMethodCallHandler(::handleMeshtasticMethod)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/meshtastic/events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                meshtasticEventSink = events
                events?.success(
                    mapOf("type" to "state", "state" to ble.state, "error" to ble.lastError),
                )
            }

            override fun onCancel(arguments: Any?) {
                meshtasticEventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/usbserial",
        ).setMethodCallHandler(::handleUsbSerialMethod)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.fpvclub.mesh/usbserial/events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                usbEventSink = events
                usbDetach?.invoke()
                usbDetach = UsbSerialRuntime.attach(
                    onState = { json ->
                        main.post {
                            usbEventSink?.success(mapOf("type" to "state", "json" to json))
                        }
                    },
                    onBytes = { base64 ->
                        main.post {
                            usbEventSink?.success(mapOf("type" to "bytes", "base64" to base64))
                        }
                    },
                )
            }

            override fun onCancel(arguments: Any?) {
                usbDetach?.invoke()
                usbDetach = null
                usbEventSink = null
            }
        })
    }

    private fun handleMapMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listPackages" -> result.success(mapPackageStore.list())
            "setActive" -> {
                try {
                    result.success(mapPackageStore.setActive(call.argument<String>("id")))
                } catch (t: Throwable) {
                    result.error("MAP_PACKAGE", t.message ?: t.toString(), null)
                }
            }
            "deletePackage" -> {
                val id = call.argument<String>("id")
                    ?: return result.error("BAD_ARGUMENT", "id required", null)
                result.success(mapPackageStore.delete(id))
            }
            "importPackage" -> {
                if (mapImportResult != null) {
                    result.error("BUSY", "map import already active", null)
                    return
                }
                mapImportResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/vnd.pmtiles", "application/octet-stream"))
                }
                startActivityForResult(intent, mapImportRequestCode)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleLocalNetworkMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissionStatus" -> result.success(localNetworkPermissionStatus())
            "requestPermission" -> requestLocalNetworkPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun handleMeshtasticMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appDataPath" -> {
                val dir = File(filesDir, "mesh-messenger")
                dir.mkdirs()
                result.success(dir.absolutePath)
            }
            "permissionStatus" -> result.success(permissionStatus())
            "diagnostics" -> result.success(diagnostics())
            "requestPermissions" -> requestBlePermissions(result)
            "scan" -> runAsync(result) {
                ble.scan().map { mapOf("id" to it.id, "name" to it.name) }
            }
            "connect" -> {
                val deviceId = call.argument<String>("deviceId")
                    ?: return result.error("BAD_ARGUMENT", "deviceId required", null)
                runAsync(result) {
                    ble.connect(deviceId)
                    null
                }
            }
            "disconnect" -> runAsync(result) {
                ble.disconnect()
                null
            }
            "sendToRadio" -> {
                val bytes = call.argument<ByteArray>("bytes")
                    ?: return result.error("BAD_ARGUMENT", "bytes required", null)
                runAsync(result) {
                    ble.sendToRadio(bytes)
                    null
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun handleUsbSerialMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "devices" -> result.success(UsbSerialRuntime.devicesJson())
            "status" -> result.success(UsbSerialRuntime.statusJson())
            "connect" -> {
                val deviceId = call.argument<Int>("deviceId")
                    ?: return result.error("BAD_ARGUMENT", "deviceId required", null)
                val baudRate = call.argument<Int>("baudRate") ?: 115200
                UsbSerialRuntime.connect(deviceId, baudRate)
                result.success(null)
            }
            "disconnect" -> {
                UsbSerialRuntime.disconnect()
                result.success(null)
            }
            "write" -> {
                val base64 = call.argument<String>("base64")
                    ?: return result.error("BAD_ARGUMENT", "base64 required", null)
                UsbSerialRuntime.writeBase64(base64)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (t: Throwable) {
                main.post { result.error("MESHTASTIC", t.message ?: t.toString(), null) }
            }
        }
    }

    private fun localNetworkPermissionStatus(): Map<String, Any> {
        val targetSdk = applicationInfo.targetSdkVersion
        val required = Build.VERSION.SDK_INT >= 37 && targetSdk >= 37
        val granted = !required || checkSelfPermission(localNetworkPermission) == PackageManager.PERMISSION_GRANTED
        return mapOf(
            "required" to required,
            "granted" to granted,
            "missing" to if (granted) emptyList<String>() else listOf(localNetworkPermission),
            "sdkInt" to Build.VERSION.SDK_INT,
            "targetSdk" to targetSdk,
        )
    }

    private fun requestLocalNetworkPermission(result: MethodChannel.Result) {
        val status = localNetworkPermissionStatus()
        if (status["granted"] == true) {
            result.success(status)
            return
        }
        if (localNetworkPermissionResult != null) {
            result.error("BUSY", "local network permission request already active", null)
            return
        }
        localNetworkPermissionResult = result
        requestPermissions(arrayOf(localNetworkPermission), localNetworkPermissionRequestCode)
    }

    private fun requiredPermissions(): List<String> = buildList {
        if (Build.VERSION.SDK_INT >= 31) {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun missingPermissions(): List<String> = requiredPermissions().filter {
        checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
    }

    private fun permissionStatus(): Map<String, Any> = mapOf(
        "granted" to missingPermissions().isEmpty(),
        "missing" to missingPermissions(),
    )

    private fun diagnostics(): Map<String, Any?> = mapOf(
        "sdkInt" to Build.VERSION.SDK_INT,
        "bluetoothEnabled" to ble.bluetoothEnabled,
        "state" to ble.state,
        "connected" to ble.isConnected,
        "lastError" to ble.lastError,
    )

    private fun requestBlePermissions(result: MethodChannel.Result) {
        val missing = missingPermissions()
        if (missing.isEmpty()) {
            result.success(permissionStatus())
            return
        }
        if (permissionResult != null) {
            result.error("BUSY", "permission request already active", null)
            return
        }
        permissionResult = result
        requestPermissions(missing.toTypedArray(), permissionRequestCode)
    }

    @Deprecated("Deprecated in Android API; kept for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != mapImportRequestCode) return
        val pending = mapImportResult
        mapImportResult = null
        if (pending == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return
        }
        executor.execute {
            try {
                runCatching {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION),
                    )
                }
                val imported = mapPackageStore.importUri(contentResolver, uri)
                main.post { pending.success(imported) }
            } catch (t: Throwable) {
                main.post { pending.error("MAP_IMPORT", t.message ?: t.toString(), null) }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val result = permissionResult
            permissionResult = null
            result?.success(permissionStatus())
        } else if (requestCode == localNetworkPermissionRequestCode) {
            val result = localNetworkPermissionResult
            localNetworkPermissionResult = null
            result?.success(localNetworkPermissionStatus())
        }
    }

    override fun onDestroy() {
        runCatching { ble.disconnect() }
        runCatching { UsbSerialRuntime.disconnect() }
        usbDetach?.invoke()
        usbDetach = null
        executor.shutdownNow()
        super.onDestroy()
    }
}
