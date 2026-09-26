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
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

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

        return try {
            port.open(connection)
            port.setParameters(
                115200,
                8,
                UsbSerialPort.STOPBITS_1,
                UsbSerialPort.PARITY_NONE,
            )

            // ELRS hardware may enter ROM manually via BOOT pad. Do not touch DTR/RTS here.
            drainInput(port)
            val link = RomLink(port)

            if (!link.sync()) {
                result(
                    status = "rom_sync_timeout",
                    message = if (link.bytesRead == 0) {
                        "USB-UART открыт, но ESP ROM не ответил. Переведите ELRS оборудование в ROM BOOT (BOOT→GND при подаче питания, если это требуется платой) и повторите проверку."
                    } else {
                        "По UART пришли данные, но ESP ROM SYNC не подтверждён. Проверьте BOOT mode и TX/RX."
                    },
                    device = device,
                    driver = driver.javaClass.simpleName,
                    bytesRead = link.bytesRead,
                    elapsedMs = System.currentTimeMillis() - started,
                )
            } else {
                val diag = inspectChip(link)
                linkedMapOf<String, Any?>(
                    "status" to "rom_ready",
                    "message" to "ESP ROM отвечает, контроллер определён",
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "deviceName" to device.deviceName,
                    "product" to runCatching { device.productName }.getOrNull(),
                    "manufacturer" to runCatching { device.manufacturerName }.getOrNull(),
                    "driver" to driver.javaClass.simpleName,
                    "baudRate" to 115200,
                    "bytesRead" to link.bytesRead,
                    "elapsedMs" to (System.currentTimeMillis() - started),
                ).apply { putAll(diag) }
            }
        } catch (e: Exception) {
            result(
                status = "serial_error",
                message = "Ошибка USB-Serial: \${e.message ?: e.javaClass.simpleName}",
                device = device,
                driver = driver.javaClass.simpleName,
                bytesRead = 0,
                elapsedMs = System.currentTimeMillis() - started,
            )
        } finally {
            runCatching { port.close() }
            runCatching { connection.close() }
        }
    }


    fun flashPrepared(
        device: UsbDevice,
        manifestPath: String,
        expectedTargetPath: String,
        expectedSha256: String,
    ): Map<String, Any?> {
        val started = System.currentTimeMillis()

        return try {
            if (!usbManager.hasPermission(device)) {
                error("Нет разрешения Android на USB-UART")
            }

            val manifestFile = File(manifestPath).canonicalFile
            val filesRoot = context.filesDir.canonicalFile
            if (!manifestFile.path.startsWith(filesRoot.path + File.separator)) {
                error("Манифест находится вне внутреннего хранилища приложения")
            }
            if (!manifestFile.isFile) error("Манифест прошивки не найден")

            val manifest = JSONObject(manifestFile.readText(Charsets.UTF_8))
            val targetPath = manifest.getString("targetPath")
            val productName = manifest.getString("productName")
            val platform = manifest.getString("platform")
            val firmwareFamily = manifest.getString("firmware")
            val hardwareSource = manifest.optString("hardwareSource")
            val region = if (manifest.has("regulatoryDomain")) {
                manifest.getString("regulatoryDomain")
            } else {
                manifest.optString("regulatoryProfile")
            }
            val offsetText = manifest.getString("writeOffset")
            val fileName = manifest.getString("fileName")
            val declaredSize = manifest.getLong("fileSize")
            val declaredSha = manifest.getString("sha256").lowercase()

            if (targetPath != expectedTargetPath) {
                error("Target прошивки не совпадает с выбранной моделью")
            }
            if (declaredSha != expectedSha256.lowercase()) {
                error("SHA-256 подготовленной прошивки изменился")
            }
            if (hardwareSource != "same firmware.zip commit") {
                error("Прошивка не прошла version-pinned hardware gate")
            }
            if (platform != "esp8285") {
                error("ROM-запись alpha.10 разрешена только для ESP8285")
            }
            if (!firmwareFamily.startsWith("Unified_ESP8285_")) {
                error("Неподдерживаемое семейство прошивки: $firmwareFamily")
            }
            if (offsetText != "0x0") {
                error("Для ESP8285 ожидается адрес записи 0x0")
            }

            val firmwareFile = File(manifestFile.parentFile, fileName).canonicalFile
            if (!firmwareFile.path.startsWith(filesRoot.path + File.separator)) {
                error("Файл прошивки находится вне внутреннего хранилища")
            }
            if (!firmwareFile.isFile) error("firmware.bin не найден")

            val firmware = firmwareFile.readBytes()
            if (firmware.size.toLong() != declaredSize) {
                error("Размер firmware.bin изменился после подготовки")
            }
            val actualSha = sha256(firmware)
            if (actualSha != declaredSha) {
                error("SHA-256 firmware.bin не совпадает с манифестом")
            }
            validateEspImage(firmware)

            val driver = probeDriver(device)
                ?: error("Для USB-UART не найден serial-драйвер")
            val connection = usbManager.openDevice(device)
                ?: error("Android не смог открыть USB-UART")
            val port = driver.ports.firstOrNull()
                ?: run {
                    connection.close()
                    error("Serial-порт USB-UART отсутствует")
                }

            try {
                port.open(connection)
                port.setParameters(
                    115200,
                    8,
                    UsbSerialPort.STOPBITS_1,
                    UsbSerialPort.PARITY_NONE,
                )
                drainInput(port)
                val link = RomLink(port)

                if (!link.sync()) {
                    error("ESP ROM не ответил. Снова войдите в BOOT mode")
                }

                val magic = link.readReg(0x40001000L)
                if (magic != 0xFFF0C101L) {
                    error("Подключён не ESP8266/ESP8285 ROM")
                }

                val diag = inspectChip(link)
                val chipDescription =
                    diag["chipDescription"]?.toString() ?: "ESP8266 / ESP8285"
                if (!chipDescription.startsWith("ESP8285")) {
                    error("Ожидался ESP8285, обнаружен $chipDescription")
                }

                val flashId = readEsp8266FlashId(link)
                val flashInfo = decodeFlashId(flashId)
                val flashSizeText = flashInfo.third
                    ?: error("Размер flash по JEDEC ID определить не удалось")
                val flashSizeBytes = parseFlashSizeBytes(flashSizeText)
                    ?: error("Не удалось разобрать размер flash: $flashSizeText")

                if (firmware.size > flashSizeBytes) {
                    error(
                        "firmware.bin ${firmware.size} Б больше flash $flashSizeBytes Б"
                    )
                }

                val blockSize = 0x400
                val blocks = (firmware.size + blockSize - 1) / blockSize
                val eraseSize = esp8266EraseSize(0, firmware.size)
                val begin = le32(eraseSize, blocks, blockSize, 0)

                if (link.command(0x02, begin, 12000) == null) {
                    error("ESP ROM не подтвердил FLASH_BEGIN")
                }

                for (seq in 0 until blocks) {
                    val start = seq * blockSize
                    val end = minOf(start + blockSize, firmware.size)
                    val data = ByteArray(blockSize) { 0xFF.toByte() }
                    firmware.copyInto(
                        destination = data,
                        destinationOffset = 0,
                        startIndex = start,
                        endIndex = end,
                    )
                    val payload = le32(blockSize, seq, 0, 0) + data
                    val checksum = espChecksum(data)

                    var acknowledged = false
                    for (attempt in 0 until 3) {
                        if (link.command(
                                op = 0x03,
                                data = payload,
                                timeoutMs = 1800,
                                checksum = checksum,
                            ) != null
                        ) {
                            acknowledged = true
                            break
                        }
                    }
                    if (!acknowledged) {
                        error("ROM не подтвердил блок ${seq + 1} из $blocks")
                    }
                }

                mapOf(
                    "status" to "flash_written",
                    "message" to "Запись завершена: ROM подтвердил все блоки. Полный readback пока не выполнялся.",
                    "targetPath" to targetPath,
                    "productName" to productName,
                    "version" to manifest.optString("version"),
                    "regulatoryDomain" to region,
                    "chipDescription" to chipDescription,
                    "flashId" to "0x%06X".format(flashId and 0xFFFFFFL),
                    "flashSize" to flashSizeText,
                    "fileSize" to firmware.size,
                    "sha256" to actualSha,
                    "blocksWritten" to blocks,
                    "blockSize" to blockSize,
                    "writeOffset" to "0x0",
                    "verification" to "rom_block_ack",
                    "needsPowerCycle" to true,
                    "elapsedMs" to (System.currentTimeMillis() - started),
                )
            } finally {
                runCatching { port.close() }
                runCatching { connection.close() }
            }
        } catch (e: Exception) {
            mapOf(
                "status" to "flash_error",
                "message" to (e.message ?: e.javaClass.simpleName),
                "elapsedMs" to (System.currentTimeMillis() - started),
            )
        }
    }

    private fun validateEspImage(bytes: ByteArray) {
        if (bytes.size < 0x1010) error("firmware.bin слишком маленький")
        if ((bytes[0].toInt() and 0xFF) != 0xE9) {
            error("firmware.bin не похож на ESP image")
        }
        val segments = bytes[1].toInt() and 0xFF
        if (segments == 2 && (bytes[0x1000].toInt() and 0xFF) != 0xE9) {
            error("Некорректный ESP8285 second image header")
        }
    }

    private fun esp8266EraseSize(offset: Int, size: Int): Int {
        val sectorsPerBlock = 16
        val sectorSize = 0x1000
        val numSectors = (size + sectorSize - 1) / sectorSize
        val startSector = offset / sectorSize
        var headSectors = sectorsPerBlock - (startSector % sectorsPerBlock)
        if (numSectors < headSectors) headSectors = numSectors

        return if (numSectors < 2 * headSectors) {
            ((numSectors + 1) / 2) * sectorSize
        } else {
            (numSectors - headSectors) * sectorSize
        }
    }

    private fun espChecksum(data: ByteArray): Long {
        var value = 0xEFL
        for (b in data) {
            value = value xor (b.toInt() and 0xFF).toLong()
        }
        return value and 0xFFFFFFFFL
    }

    private fun parseFlashSizeBytes(text: String): Int? {
        val clean = text.trim().uppercase()
        return when {
            clean.endsWith("MB") ->
                clean.removeSuffix("MB").toIntOrNull()?.times(1024 * 1024)
            clean.endsWith("KB") ->
                clean.removeSuffix("KB").toIntOrNull()?.times(1024)
            else -> null
        }
    }

    private fun sha256(bytes: ByteArray): String {
        return MessageDigest
            .getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }

    private fun inspectChip(link: RomLink): Map<String, Any?> {
        val magic = link.readReg(0x40001000L)
        if (magic == null) {
            return mapOf(
                "chipFamily" to "Espressif",
                "chipDescription" to "ROM bootloader",
                "chipMagic" to null,
            )
        }

        if (magic == 0xFFF0C101L) {
            val r0 = link.readReg(0x3FF00050L)
            val r1 = link.readReg(0x3FF00054L)
            val r2 = link.readReg(0x3FF00058L)
            val r3 = link.readReg(0x3FF0005CL)

            val chipDescription = if (r0 != null && r2 != null && r3 != null) {
                esp8266Description(r0, r2, r3)
            } else {
                "ESP8266 / ESP8285"
            }

            val chipId = if (r0 != null && r1 != null) {
                ((r0 ushr 24) or ((r1 and 0xFFFFFFL) shl 8)) and 0xFFFFFFFFL
            } else null

            val mac = if (r0 != null && r1 != null && r3 != null) {
                esp8266Mac(r0, r1, r3)
            } else null

            val flashId = runCatching { readEsp8266FlashId(link) }.getOrNull()
            val flashInfo = flashId?.let { decodeFlashId(it) }

            return linkedMapOf(
                "chipFamily" to "ESP8266",
                "chipDescription" to chipDescription,
                "chipMagic" to hex32(magic),
                "chipId" to chipId?.let { hex32(it) },
                "mac" to mac,
                "flashId" to flashId?.let { hex24(it) },
                "flashVendorId" to flashInfo?.first,
                "flashDeviceId" to flashInfo?.second,
                "flashSize" to flashInfo?.third,
                "flashEmbedded" to chipDescription.startsWith("ESP8285"),
            )
        }

        return linkedMapOf(
            "chipFamily" to when (magic) {
                0x00F01D83L -> "ESP32"
                0x000007C6L -> "ESP32-S2"
                else -> "Espressif"
            },
            "chipDescription" to when (magic) {
                0x00F01D83L -> "ESP32"
                0x000007C6L -> "ESP32-S2"
                else -> "Неизвестный Espressif ROM"
            },
            "chipMagic" to hex32(magic),
        )
    }

    private fun esp8266Description(r0: Long, r2: Long, r3: Long): String {
        val is8285 = (r0 and (1L shl 4)) != 0L || (r2 and (1L shl 16)) != 0L
        if (!is8285) return "ESP8266EX"

        val r0Bit4 = (r0 and (1L shl 4)) != 0L
        val r3Bit25 = (r3 and (1L shl 25)) != 0L
        val r3Bit26 = (r3 and (1L shl 26)) != 0L
        val r3Bit27 = (r3 and (1L shl 27)) != 0L

        val sizeMb = when {
            r0Bit4 && !r3Bit25 && !r3Bit27 && !r3Bit26 -> 1
            r0Bit4 && !r3Bit25 && !r3Bit27 && r3Bit26 -> 2
            !r0Bit4 && r3Bit25 && !r3Bit27 && !r3Bit26 -> 2
            !r0Bit4 && r3Bit25 && !r3Bit27 && r3Bit26 -> 4
            else -> -1
        }

        val highTemp = (r0 and (1L shl 5)) != 0L
        return when (sizeMb) {
            1 -> if (highTemp) "ESP8285H08" else "ESP8285N08"
            2 -> if (highTemp) "ESP8285H16" else "ESP8285N16"
            else -> "ESP8285"
        }
    }

    private fun esp8266Mac(r0: Long, r1: Long, r3: Long): String? {
        val oui = when {
            r3 != 0L -> intArrayOf(
                ((r3 ushr 16) and 0xFF).toInt(),
                ((r3 ushr 8) and 0xFF).toInt(),
                (r3 and 0xFF).toInt(),
            )
            ((r1 ushr 16) and 0xFF) == 0L -> intArrayOf(0x18, 0xFE, 0x34)
            ((r1 ushr 16) and 0xFF) == 1L -> intArrayOf(0xAC, 0xD0, 0x74)
            else -> return null
        }

        val bytes = intArrayOf(
            oui[0], oui[1], oui[2],
            ((r1 ushr 8) and 0xFF).toInt(),
            (r1 and 0xFF).toInt(),
            ((r0 ushr 24) and 0xFF).toInt(),
        )
        return bytes.joinToString(":") { "%02X".format(it) }
    }

    private fun readEsp8266FlashId(link: RomLink): Long {
        link.command(0x02, le32(0, 0, 0x400, 0), 800)
            ?: error("FLASH_BEGIN(0,0) failed")

        val spiBase = 0x60000200L
        val cmdReg = spiBase + 0x00
        val usrReg = spiBase + 0x1C
        val usr1Reg = spiBase + 0x20
        val usr2Reg = spiBase + 0x24
        val w0Reg = spiBase + 0x40

        val oldUsr = link.readReg(usrReg) ?: error("SPI_USR read failed")
        val oldUsr2 = link.readReg(usr2Reg) ?: error("SPI_USR2 read failed")

        val spiUsrCommand = 1L shl 31
        val spiUsrMiso = 1L shl 28
        val spiCmdUsr = 1L shl 18

        link.writeReg(usr1Reg, 23L shl 8)
        link.writeReg(usrReg, spiUsrCommand or spiUsrMiso)
        link.writeReg(usr2Reg, (7L shl 28) or 0x9FL)
        link.writeReg(w0Reg, 0)
        link.writeReg(cmdReg, spiCmdUsr)

        var done = false
        repeat(20) {
            val cmd = link.readReg(cmdReg) ?: 0L
            if ((cmd and spiCmdUsr) == 0L) done = true
            if (!done) Thread.sleep(5)
        }
        if (!done) error("SPI RDID timeout")

        val id = link.readReg(w0Reg) ?: error("SPI flash ID read failed")
        link.writeReg(usrReg, oldUsr)
        link.writeReg(usr2Reg, oldUsr2)
        return id and 0xFFFFFFL
    }

    private fun decodeFlashId(id: Long): Triple<Int, String, String?> {
        val vendor = (id and 0xFF).toInt()
        val device = (((id ushr 16) and 0xFF) or (((id ushr 8) and 0xFF) shl 8)).toInt()
        val sizeId = if (vendor == 0x1F) {
            ((id ushr 8) and 0x1F).toInt()
        } else {
            ((id ushr 16) and 0xFF).toInt()
        }

        val size = if (vendor == 0x1F) {
            mapOf(
                0x04 to "512KB", 0x05 to "1MB", 0x06 to "2MB",
                0x07 to "4MB", 0x08 to "8MB", 0x09 to "16MB",
            )[sizeId]
        } else {
            mapOf(
                0x12 to "256KB", 0x13 to "512KB", 0x14 to "1MB", 0x15 to "2MB",
                0x16 to "4MB", 0x17 to "8MB", 0x18 to "16MB", 0x19 to "32MB",
                0x1A to "64MB", 0x1B to "128MB", 0x1C to "256MB",
                0x20 to "64MB", 0x21 to "128MB", 0x22 to "256MB",
                0x32 to "256KB", 0x33 to "512KB", 0x34 to "1MB", 0x35 to "2MB",
                0x36 to "4MB", 0x37 to "8MB", 0x38 to "16MB", 0x39 to "32MB",
                0x3A to "64MB",
            )[sizeId]
        }
        return Triple(vendor, "0x%04X".format(device), size)
    }

    private fun hex32(v: Long) = "0x%08X".format(v and 0xFFFFFFFFL)
    private fun hex24(v: Long) = "0x%06X".format(v and 0xFFFFFFL)

    private fun le32(vararg values: Int): ByteArray {
        val b = ByteBuffer.allocate(values.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        values.forEach { b.putInt(it) }
        return b.array()
    }

    private class RomLink(private val port: UsbSerialPort) {
        var bytesRead: Int = 0
            private set

        fun sync(): Boolean {
            val payload = ByteArrayOutputStream().apply {
                write(byteArrayOf(0x07, 0x07, 0x12, 0x20))
                repeat(32) { write(0x55) }
            }.toByteArray()

            repeat(5) {
                if (command(0x08, payload, 650) != null) return true
                Thread.sleep(80)
            }
            return false
        }

        fun readReg(addr: Long): Long? {
            val data = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
                .putInt(addr.toInt()).array()
            return command(0x0A, data, 600)?.value
        }

        fun writeReg(
            addr: Long,
            value: Long,
            mask: Long = 0xFFFFFFFFL,
            delayUs: Long = 0,
        ): Boolean {
            val data = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN)
                .putInt(addr.toInt())
                .putInt(value.toInt())
                .putInt(mask.toInt())
                .putInt(delayUs.toInt())
                .array()
            return command(0x09, data, 600) != null
        }

        fun command(
            op: Int,
            data: ByteArray,
            timeoutMs: Long,
            checksum: Long = 0,
        ): RomResponse? {
            val request = ByteBuffer.allocate(8 + data.size)
                .order(ByteOrder.LITTLE_ENDIAN)
                .put(0x00)
                .put(op.toByte())
                .putShort(data.size.toShort())
                .putInt(checksum.toInt())
                .put(data)
                .array()

            port.write(slipEncode(request), 1200)
            val raw = readFor(timeoutMs)

            for (frame in parseSlipFrames(raw)) {
                if (frame.size < 8) continue
                val response = frame[0].toInt() and 0xFF
                val responseOp = frame[1].toInt() and 0xFF
                if (response != 1 || responseOp != op) continue

                val len = (frame[2].toInt() and 0xFF) or
                    ((frame[3].toInt() and 0xFF) shl 8)
                val value = ByteBuffer.wrap(frame, 4, 4)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .int
                    .toLong() and 0xFFFFFFFFL

                val payloadEnd = minOf(frame.size, 8 + len)
                val responseData = if (payloadEnd > 8) {
                    frame.copyOfRange(8, payloadEnd)
                } else {
                    byteArrayOf()
                }

                if (responseData.size >= 2 && responseData[0].toInt() != 0) {
                    continue
                }
                return RomResponse(value, responseData)
            }
            return null
        }

        private fun readFor(durationMs: Long): ByteArray {
            val out = ByteArrayOutputStream()
            val buf = ByteArray(2048)
            val until = System.currentTimeMillis() + durationMs
            while (System.currentTimeMillis() < until) {
                val n = try {
                    port.read(buf, 80)
                } catch (_: Exception) {
                    0
                }
                if (n > 0) {
                    out.write(buf, 0, n)
                    bytesRead += n
                }
            }
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

        private fun parseSlipFrames(raw: ByteArray): List<ByteArray> {
            val frames = mutableListOf<ByteArray>()
            var cur = ByteArrayOutputStream()
            var inFrame = false
            var escaped = false

            for (b in raw) {
                val x = b.toInt() and 0xFF

                if (x == 0xC0) {
                    if (inFrame && cur.size() > 0) frames += cur.toByteArray()
                    cur = ByteArrayOutputStream()
                    inFrame = true
                    escaped = false
                    continue
                }

                if (!inFrame) continue

                if (escaped) {
                    when (x) {
                        0xDC -> cur.write(0xC0)
                        0xDD -> cur.write(0xDB)
                        else -> cur.write(x)
                    }
                    escaped = false
                } else if (x == 0xDB) {
                    escaped = true
                } else {
                    cur.write(x)
                }
            }

            if (inFrame && cur.size() > 0) frames += cur.toByteArray()
            return frames
        }
    }

    private data class RomResponse(val value: Long, val data: ByteArray)

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
