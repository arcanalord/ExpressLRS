package com.arcanalord.service_studio

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import com.hoho.android.usbserial.driver.Ch34xSerialDriver
import com.hoho.android.usbserial.driver.ProbeTable
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import java.io.ByteArrayOutputStream

class UsbSerialProbe(private val context: Context) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

    fun findDevice(deviceName: String?): UsbDevice? {
        val devices = usbManager.deviceList.values.toList()
        if (!deviceName.isNullOrBlank()) {
            devices.firstOrNull { it.deviceName == deviceName }?.let { return it }
        }
        return devices.firstOrNull { probeDriver(it) != null } ?: devices.firstOrNull()
    }

    fun hasPermission(device: UsbDevice): Boolean = usbManager.hasPermission(device)

    fun probe(device: UsbDevice): Map<String, Any?> {
        val started = System.currentTimeMillis()

        if (!usbManager.hasPermission(device)) {
            return result(
                status = "no_permission",
                message = "Нет разрешения Android на USB-устройство",
                device = device,
                driver = null,
                bytesRead = 0,
                elapsedMs = 0,
            )
        }

        val driver = probeDriver(device)
            ?: return result(
                status = "no_driver",
                message = "Для этого USB-UART не найден serial-драйвер",
                device = device,
                driver = null,
                bytesRead = 0,
                elapsedMs = System.currentTimeMillis() - started,
            )

        val connection = usbManager.openDevice(device)
            ?: return result(
                status = "open_failed",
                message = "Android не смог открыть USB-устройство",
                device = device,
                driver = driver.javaClass.simpleName,
                bytesRead = 0,
                elapsedMs = System.currentTimeMillis() - started,
            )

        val port = driver.ports.firstOrNull()
            ?: run {
                connection.close()
                return result(
                    status = "no_port",
                    message = "USB-UART найден, но serial-порт отсутствует",
                    device = device,
                    driver = driver.javaClass.simpleName,
                    bytesRead = 0,
                    elapsedMs = System.currentTimeMillis() - started,
                )
            }

        var bytesRead = 0
        return try {
            port.open(connection)
            port.setParameters(
                115200,
                8,
                UsbSerialPort.STOPBITS_1,
                UsbSerialPort.PARITY_NONE,
            )

            // Не дёргаем DTR/RTS: для EP2 вход в ROM выполняется вручную через BOOT pad.
            drainInput(port)

            val packet = slipEncode(buildSyncRequest())
            var synced = false
            var lastRaw = byteArrayOf()

            repeat(5) {
                port.write(packet, 1200)
                val raw = readFor(port, 500)
                bytesRead += raw.size
                if (raw.isNotEmpty()) lastRaw = raw
                if (containsSyncResponse(raw)) {
                    synced = true
                    return@repeat
                }
                Thread.sleep(80)
            }

            if (synced) {
                result(
                    status = "rom_sync_ok",
                    message = "ROM-загрузчик ESP отвечает",
                    device = device,
                    driver = driver.javaClass.simpleName,
                    bytesRead = bytesRead,
                    elapsedMs = System.currentTimeMillis() - started,
                )
            } else {
                result(
                    status = "rom_sync_timeout",
                    message = if (lastRaw.isEmpty()) {
                        "USB-UART открыт, но ESP ROM не ответил. Для EP2 замкните BOOT pad на GND при подаче питания и повторите проверку."
                    } else {
                        "Данные по UART получены, но ответа ESP ROM SYNC нет. Проверьте BOOT mode и TX/RX."
                    },
                    device = device,
                    driver = driver.javaClass.simpleName,
                    bytesRead = bytesRead,
                    elapsedMs = System.currentTimeMillis() - started,
                )
            }
        } catch (e: Exception) {
            result(
                status = "serial_error",
                message = "Ошибка USB-Serial: ${e.message ?: e.javaClass.simpleName}",
                device = device,
                driver = driver.javaClass.simpleName,
                bytesRead = bytesRead,
                elapsedMs = System.currentTimeMillis() - started,
            )
        } finally {
            runCatching { port.close() }
            runCatching { connection.close() }
        }
    }

    private fun probeDriver(device: UsbDevice): UsbSerialDriver? {
        UsbSerialProber.getDefaultProber().probeDevice(device)?.let { return it }

        // WCH CH34x/CH343 variants seen on our adapters, including 0x55d3.
        if (device.vendorId == 0x1A86) {
            val table = ProbeTable().apply {
                addProduct(0x1A86, 0x55D3, Ch34xSerialDriver::class.java)
                addProduct(0x1A86, 0x7523, Ch34xSerialDriver::class.java)
                addProduct(0x1A86, 0x5523, Ch34xSerialDriver::class.java)
            }
            return UsbSerialProber(table).probeDevice(device)
        }

        return null
    }

    private fun drainInput(port: UsbSerialPort) {
        val buf = ByteArray(512)
        repeat(3) {
            runCatching { port.read(buf, 40) }
        }
    }

    private fun buildSyncRequest(): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(0x00) // request direction
        out.write(0x08) // ESP ROM SYNC command
        out.write(0x24) // payload length = 36
        out.write(0x00)
        repeat(4) { out.write(0x00) } // checksum

        out.write(0x07)
        out.write(0x07)
        out.write(0x12)
        out.write(0x20)
        repeat(32) { out.write(0x55) }
        return out.toByteArray()
    }

    private fun slipEncode(body: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(0xC0)
        for (b in body) {
            when (b.toInt() and 0xFF) {
                0xC0 -> {
                    out.write(0xDB)
                    out.write(0xDC)
                }
                0xDB -> {
                    out.write(0xDB)
                    out.write(0xDD)
                }
                else -> out.write(b.toInt() and 0xFF)
            }
        }
        out.write(0xC0)
        return out.toByteArray()
    }

    private fun readFor(port: UsbSerialPort, durationMs: Long): ByteArray {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(2048)
        val until = System.currentTimeMillis() + durationMs

        while (System.currentTimeMillis() < until) {
            val n = try {
                port.read(buf, 80)
            } catch (_: Exception) {
                0
            }
            if (n > 0) out.write(buf, 0, n)
        }

        return out.toByteArray()
    }

    private fun containsSyncResponse(raw: ByteArray): Boolean {
        var frame = ByteArrayOutputStream()
        var inFrame = false
        var escaped = false

        fun checkFrame(): Boolean {
            val b = frame.toByteArray()
            return b.size >= 2 &&
                (b[0].toInt() and 0xFF) == 0x01 &&
                (b[1].toInt() and 0xFF) == 0x08
        }

        for (v in raw) {
            val x = v.toInt() and 0xFF

            if (x == 0xC0) {
                if (inFrame && frame.size() > 0 && checkFrame()) return true
                frame = ByteArrayOutputStream()
                inFrame = true
                escaped = false
                continue
            }

            if (!inFrame) continue

            if (escaped) {
                when (x) {
                    0xDC -> frame.write(0xC0)
                    0xDD -> frame.write(0xDB)
                    else -> frame.write(x)
                }
                escaped = false
                continue
            }

            if (x == 0xDB) {
                escaped = true
            } else {
                frame.write(x)
            }
        }

        return inFrame && frame.size() > 0 && checkFrame()
    }

    private fun result(
        status: String,
        message: String,
        device: UsbDevice,
        driver: String?,
        bytesRead: Int,
        elapsedMs: Long,
    ): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "message" to message,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceName" to device.deviceName,
            "product" to runCatching { device.productName }.getOrNull(),
            "manufacturer" to runCatching { device.manufacturerName }.getOrNull(),
            "driver" to driver,
            "baudRate" to 115200,
            "bytesRead" to bytesRead,
            "elapsedMs" to elapsedMs,
        )
    }
}
