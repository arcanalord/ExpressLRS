package com.arcanalord.service_studio

import android.content.Context
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.zip.ZipInputStream

class OfficialElrsService(private val context: Context) {
    companion object {
        private const val RELEASES_LATEST =
            "https://api.github.com/repos/ExpressLRS/ExpressLRS/releases/latest"
        private const val COMMITS_API =
            "https://api.github.com/repos/ExpressLRS/ExpressLRS/commits/"
        private const val TARGETS_URL =
            "https://raw.githubusercontent.com/ExpressLRS/Targets/master/targets.json"
        private const val TARGETS_RAW_BASE =
            "https://raw.githubusercontent.com/ExpressLRS/Targets/master"
        private const val CACHE_BASE =
            "https://artifactory.expresslrs.org/ExpressLRS"
        private const val EXPECTED_FIRMWARE_8285_2400 =
            "Unified_ESP8285_2400_RX"
    }

    data class Catalog(
        val version: String,
        val releaseName: String,
        val publishedAt: String?,
        val commitSha: String,
        val targetPath: String,
        val productName: String,
        val luaName: String,
        val platform: String,
        val firmware: String,
        val layoutFile: String,
        val minVersion: String?,
        val uploadMethods: List<String>,
        val priorTargetName: String?,
    ) {
        fun asMap(): Map<String, Any?> = mapOf(
            "status" to "ok",
            "version" to version,
            "releaseName" to releaseName,
            "publishedAt" to publishedAt,
            "commitSha" to commitSha,
            "targetPath" to targetPath,
            "productName" to productName,
            "luaName" to luaName,
            "platform" to platform,
            "firmware" to firmware,
            "layoutFile" to layoutFile,
            "minVersion" to minVersion,
            "uploadMethods" to uploadMethods,
            "priorTargetName" to priorTargetName,
        )
    }

    fun fetchCatalog(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
    ): Map<String, Any?> {
        return try {
            fetchCatalogInternal(
                targetPath = targetPath,
                expectedProductName = expectedProductName,
                expectedPlatform = expectedPlatform,
                expectedFirmware = expectedFirmware,
            ).asMap()
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось получить официальный каталог ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    fun prepareFirmware(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
        regulatoryProfile: String,
    ): Map<String, Any?> {
        return try {
            if (regulatoryProfile != "FCC" && regulatoryProfile != "LBT") {
                error("Не выбран радиорегион FCC или LBT")
            }

            val catalog = fetchCatalogInternal(
                targetPath = targetPath,
                expectedProductName = expectedProductName,
                expectedPlatform = expectedPlatform,
                expectedFirmware = expectedFirmware,
            )
            val target = fetchTarget(targetPath)

            val generic = downloadCachedFirmware(
                commitSha = catalog.commitSha,
                regulatoryProfile = regulatoryProfile,
                firmwareTarget = catalog.firmware,
            )

            val hwDir = if (targetPath.split('.').getOrNull(1)?.startsWith("tx_") == true) {
                "TX"
            } else {
                "RX"
            }
            val layoutUrl =
                "$TARGETS_RAW_BASE/$hwDir/${urlPath(catalog.layoutFile)}"
            val layout = JSONObject(httpGetText(layoutUrl))

            val overlay = target.optJSONObject("overlay")
            if (overlay != null) {
                val keys = overlay.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    layout.put(key, overlay.get(key))
                }
            }

            val configured = configureUnifiedEspFirmware(
                source = generic,
                productName = catalog.productName,
                luaName = catalog.luaName,
                layoutJson = layout.toString(),
                priorTargetName = catalog.priorTargetName,
            )

            val targetSlug = targetPath
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
                .replace('.', '-')
            val dir = File(
                context.filesDir,
                "firmware/elrs/${catalog.version}/$targetSlug/$regulatoryProfile",
            )
            if (!dir.exists() && !dir.mkdirs()) {
                error("Не удалось создать каталог прошивки")
            }

            val out = File(dir, "firmware.bin")
            out.writeBytes(configured)

            mapOf(
                "status" to "prepared",
                "message" to "Официальная прошивка ExpressLRS скачана и подготовлена для ${catalog.productName}",
                "version" to catalog.version,
                "releaseName" to catalog.releaseName,
                "commitSha" to catalog.commitSha,
                "targetPath" to catalog.targetPath,
                "productName" to catalog.productName,
                "platform" to catalog.platform,
                "firmware" to catalog.firmware,
                "regulatoryProfile" to regulatoryProfile,
                "writeOffset" to "0x0",
                "filePath" to out.absolutePath,
                "fileSize" to out.length(),
                "sha256" to sha256(configured),
                "readyToFlash" to true,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось подготовить прошивку ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    private fun fetchCatalogInternal(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
    ): Catalog {
        validateSpec(
            targetPath = targetPath,
            expectedProductName = expectedProductName,
            expectedPlatform = expectedPlatform,
            expectedFirmware = expectedFirmware,
        )

        val release = JSONObject(httpGetText(RELEASES_LATEST))
        val tag = release.getString("tag_name")
        val releaseName = release.optString("name", tag)
        val publishedAt = release.optString("published_at").ifBlank { null }

        val commit = JSONObject(
            httpGetText(COMMITS_API + URLEncoder.encode(tag, "UTF-8"))
        )
        val sha = commit.getString("sha")
        val target = fetchTarget(targetPath)

        val product = target.getString("product_name")
        val platform = target.getString("platform")
        val firmware = target.getString("firmware")

        if (product != expectedProductName) {
            error("Официальный target изменился: ожидался «$expectedProductName», получен «$product»")
        }
        if (platform != expectedPlatform) {
            error("Официальная платформа изменилась: ожидалась $expectedPlatform, получена $platform")
        }
        if (firmware != expectedFirmware) {
            error("Официальное семейство прошивки изменилось: ожидалось $expectedFirmware, получено $firmware")
        }

        val methods = mutableListOf<String>()
        val arr = target.getJSONArray("upload_methods")
        for (i in 0 until arr.length()) methods += arr.getString(i)
        if (!methods.contains("uart")) {
            error("Официальный target больше не разрешает UART")
        }

        return Catalog(
            version = tag,
            releaseName = releaseName,
            publishedAt = publishedAt,
            commitSha = sha,
            targetPath = targetPath,
            productName = product,
            luaName = target.optString("lua_name", product.take(16)),
            platform = platform,
            firmware = firmware,
            layoutFile = target.getString("layout_file"),
            minVersion = target.optString("min_version").ifBlank { null },
            uploadMethods = methods,
            priorTargetName = target.optString("prior_target_name").ifBlank { null },
        )
    }

    private fun validateSpec(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
    ) {
        val parts = targetPath.split('.')
        if (parts.size != 3 || parts.any { !it.matches(Regex("[A-Za-z0-9_-]+")) }) {
            error("Некорректный путь target: $targetPath")
        }
        if (expectedProductName.isBlank()) error("Не задано имя target")
        if (expectedPlatform != "esp8285") {
            error("В alpha.7 официальный автоподбор разрешён только для ESP8285")
        }
        if (expectedFirmware != EXPECTED_FIRMWARE_8285_2400) {
            error("В alpha.7 разрешено только семейство $EXPECTED_FIRMWARE_8285_2400")
        }
    }

    private fun fetchTarget(targetPath: String): JSONObject {
        var node = JSONObject(httpGetText(TARGETS_URL))
        for (part in targetPath.split('.')) {
            node = node.getJSONObject(part)
        }
        return node
    }

    private fun downloadCachedFirmware(
        commitSha: String,
        regulatoryProfile: String,
        firmwareTarget: String,
    ): ByteArray {
        val url = "$CACHE_BASE/$commitSha/firmware.zip"
        val expectedEntry =
            "$regulatoryProfile/$firmwareTarget/firmware.bin"

        val conn = open(url)
        conn.connectTimeout = 15000
        conn.readTimeout = 60000
        conn.connect()

        if (conn.responseCode !in 200..299) {
            val code = conn.responseCode
            conn.disconnect()
            error("официальный cache ExpressLRS HTTP $code")
        }

        try {
            ZipInputStream(BufferedInputStream(conn.inputStream)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val name = entry.name.replace('\\', '/')
                    if (!entry.isDirectory && name.endsWith(expectedEntry)) {
                        val out = ByteArrayOutputStream()
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = zip.read(buf)
                            if (n <= 0) break
                            out.write(buf, 0, n)
                        }
                        val bytes = out.toByteArray()
                        if (bytes.size < 64 * 1024) {
                            error("получен слишком маленький firmware.bin")
                        }
                        return bytes
                    }
                    zip.closeEntry()
                }
            }
        } finally {
            conn.disconnect()
        }

        error("В официальном cache не найден $expectedEntry")
    }

    private fun configureUnifiedEspFirmware(
        source: ByteArray,
        productName: String,
        luaName: String,
        layoutJson: String,
        priorTargetName: String?,
    ): ByteArray {
        val end = findFirmwareEnd(source)
        if (end <= 0 || end > source.size) {
            error("не удалось определить конец ESP firmware image")
        }

        val discriminator = SecureRandom().nextInt().toLong() and 0xFFFFFFFFL
        val defines = JSONObject()
            .put("flash-discriminator", discriminator)
            .toString()

        val priorBytes = if (priorTargetName.isNullOrBlank()) {
            byteArrayOf()
        } else {
            byteArrayOf(0xBE.toByte(), 0xEF.toByte(), 0xCA.toByte(), 0xFE.toByte()) +
                priorTargetName.uppercase().toByteArray(Charsets.UTF_8) +
                byteArrayOf(0)
        }

        val metadataSize = 128 + 16 + 512 + 2048 + priorBytes.size
        val configured = source.copyOf(maxOf(source.size, end + metadataSize))
        var pos = end

        pos = writeFixed(configured, pos, productName.toByteArray(Charsets.UTF_8), 128)
        pos = writeFixed(configured, pos, luaName.toByteArray(Charsets.UTF_8), 16)
        pos = writeFixed(configured, pos, defines.toByteArray(Charsets.UTF_8), 512)
        pos = writeFixed(configured, pos, layoutJson.toByteArray(Charsets.UTF_8), 2048)

        if (priorBytes.isNotEmpty()) {
            priorBytes.copyInto(configured, destinationOffset = pos)
        }

        return configured
    }

    private fun findFirmwareEnd(bytes: ByteArray): Int {
        fun u8(i: Int) = bytes[i].toInt() and 0xFF
        fun le32(i: Int): Int =
            (u8(i)) or
                (u8(i + 1) shl 8) or
                (u8(i + 2) shl 16) or
                (u8(i + 3) shl 24)

        if (bytes.size < 0x1010 || u8(0) != 0xE9) {
            error("firmware.bin не похож на ESP image")
        }

        var segments = u8(1)
        var pos: Int
        var is8285 = false

        if (segments == 2) {
            if (u8(0x1000) != 0xE9) {
                error("ESP8285 second image header not found")
            }
            segments = u8(0x1001)
            pos = 0x1000 + 8
            is8285 = true
        } else {
            pos = 24
        }

        repeat(segments) {
            if (pos + 8 > bytes.size) error("ESP segment header outside image")
            val size = le32(pos + 4)
            if (size < 0 || pos + 8 + size > bytes.size) {
                error("ESP segment outside image")
            }
            pos += 8 + size
        }

        pos = (pos + 16) and 15.inv()
        if (!is8285) pos += 32
        return pos
    }

    private fun writeFixed(
        out: ByteArray,
        offset: Int,
        data: ByteArray,
        size: Int,
    ): Int {
        if (offset < 0 || offset + size > out.size) {
            error("Unified metadata outside firmware buffer")
        }
        val n = minOf(data.size, size)
        data.copyInto(
            destination = out,
            destinationOffset = offset,
            startIndex = 0,
            endIndex = n,
        )
        out.fill(0, fromIndex = offset + n, toIndex = offset + size)
        return offset + size
    }

    private fun httpGetText(url: String): String {
        val conn = open(url)
        conn.connectTimeout = 12000
        conn.readTimeout = 20000
        conn.setRequestProperty(
            "Accept",
            "application/vnd.github+json, application/json, text/plain",
        )
        conn.connect()

        try {
            if (conn.responseCode !in 200..299) {
                error("HTTP ${conn.responseCode} для $url")
            }
            return conn.inputStream.bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun open(url: String): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("User-Agent", "ESP-Service-Studio/0.9")
            setRequestProperty("Accept-Encoding", "identity")
            instanceFollowRedirects = true
        }
    }

    private fun urlPath(name: String): String {
        return name.split('/').joinToString("/") {
            URLEncoder.encode(it, "UTF-8").replace("+", "%20")
        }
    }

    private fun sha256(bytes: ByteArray): String {
        return MessageDigest
            .getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }
}
