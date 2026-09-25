package com.arcanalord.service_studio

import android.content.Context
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.ByteBuffer
import java.nio.ByteOrder
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

        private const val EP2_TARGET_PATH = "happymodel.rx_2400.ep"
        private const val EP2_EXPECTED_PRODUCT = "HappyModel EP1/EP2 2.4GHz RX"
        private const val EP2_EXPECTED_PLATFORM = "esp8285"
        private const val EP2_EXPECTED_FIRMWARE = "Unified_ESP8285_2400_RX"
    }

    data class Catalog(
        val version: String,
        val releaseName: String,
        val publishedAt: String?,
        val commitSha: String,
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
            "targetPath" to EP2_TARGET_PATH,
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

    fun fetchEp2Catalog(): Map<String, Any?> {
        return try {
            fetchCatalog().asMap()
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось получить официальный каталог ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    fun prepareEp2Firmware(regulatoryProfile: String): Map<String, Any?> {
        return try {
            if (regulatoryProfile != "FCC" && regulatoryProfile != "LBT") {
                error("Не выбран радиорегион FCC или LBT")
            }

            val catalog = fetchCatalog()
            val generic = downloadCachedFirmware(
                commitSha = catalog.commitSha,
                regulatoryProfile = regulatoryProfile,
                firmwareTarget = catalog.firmware,
            )

            val layoutUrl =
                "$TARGETS_RAW_BASE/RX/${urlPath(catalog.layoutFile)}"
            val layoutJson = httpGetText(layoutUrl)
            val layout = JSONObject(layoutJson)

            val target = fetchEp2Target()
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

            val dir = File(
                context.filesDir,
                "firmware/elrs/${catalog.version}/happymodel-ep/$regulatoryProfile",
            )
            if (!dir.exists() && !dir.mkdirs()) {
                error("Не удалось создать каталог прошивки")
            }

            val out = File(dir, "firmware.bin")
            out.writeBytes(configured)

            val sha256 = sha256(configured)
            mapOf(
                "status" to "prepared",
                "message" to "Официальная прошивка ExpressLRS скачана и подготовлена для EP1/EP2",
                "version" to catalog.version,
                "releaseName" to catalog.releaseName,
                "commitSha" to catalog.commitSha,
                "targetPath" to EP2_TARGET_PATH,
                "productName" to catalog.productName,
                "platform" to catalog.platform,
                "firmware" to catalog.firmware,
                "regulatoryProfile" to regulatoryProfile,
                "writeOffset" to "0x0",
                "filePath" to out.absolutePath,
                "fileSize" to out.length(),
                "sha256" to sha256,
                "readyToFlash" to true,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось подготовить прошивку ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    private fun fetchCatalog(): Catalog {
        val release = JSONObject(httpGetText(RELEASES_LATEST))
        val tag = release.getString("tag_name")
        val releaseName = release.optString("name", tag)
        val publishedAt = release.optString("published_at").ifBlank { null }

        val commit = JSONObject(
            httpGetText(COMMITS_API + URLEncoder.encode(tag, "UTF-8"))
        )
        val sha = commit.getString("sha")

        val target = fetchEp2Target()

        val product = target.getString("product_name")
        val platform = target.getString("platform")
        val firmware = target.getString("firmware")

        if (product != EP2_EXPECTED_PRODUCT) {
            error("Официальный target EP2 изменился: $product")
        }
        if (platform != EP2_EXPECTED_PLATFORM) {
            error("Официальная платформа EP2 изменилась: $platform")
        }
        if (firmware != EP2_EXPECTED_FIRMWARE) {
            error("Официальное семейство прошивки EP2 изменилось: $firmware")
        }

        val methods = mutableListOf<String>()
        val arr = target.getJSONArray("upload_methods")
        for (i in 0 until arr.length()) methods += arr.getString(i)
        if (!methods.contains("uart")) {
            error("Официальный target EP2 больше не разрешает UART")
        }

        return Catalog(
            version = tag,
            releaseName = releaseName,
            publishedAt = publishedAt,
            commitSha = sha,
            productName = product,
            luaName = target.optString("lua_name", "HM EP 2400"),
            platform = platform,
            firmware = firmware,
            layoutFile = target.getString("layout_file"),
            minVersion = target.optString("min_version").ifBlank { null },
            uploadMethods = methods,
            priorTargetName = target.optString("prior_target_name").ifBlank { null },
        )
    }

    private fun fetchEp2Target(): JSONObject {
        val root = JSONObject(httpGetText(TARGETS_URL))
        return root
            .getJSONObject("happymodel")
            .getJSONObject("rx_2400")
            .getJSONObject("ep")
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

        val out = ByteArrayOutputStream(source.size + 3000)
        out.write(source)

        while (out.size() < end) out.write(0)

        writeFixed(out, productName.toByteArray(Charsets.UTF_8), 128)
        writeFixed(out, luaName.toByteArray(Charsets.UTF_8), 16)
        writeFixed(out, defines.toByteArray(Charsets.UTF_8), 512)
        writeFixed(out, layoutJson.toByteArray(Charsets.UTF_8), 2048)

        if (!priorTargetName.isNullOrBlank()) {
            out.write(byteArrayOf(0xBE.toByte(), 0xEF.toByte(), 0xCA.toByte(), 0xFE.toByte()))
            out.write(priorTargetName.uppercase().toByteArray(Charsets.UTF_8))
            out.write(0)
        }

        return out.toByteArray()
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
            if (u8(0x1000) != 0xE9) error("ESP8285 second image header not found")
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
        out: ByteArrayOutputStream,
        data: ByteArray,
        size: Int,
    ) {
        val n = minOf(data.size, size)
        out.write(data, 0, n)
        repeat(size - n) { out.write(0) }
    }

    private fun httpGetText(url: String): String {
        val conn = open(url)
        conn.connectTimeout = 12000
        conn.readTimeout = 20000
        conn.setRequestProperty("Accept", "application/vnd.github+json, application/json, text/plain")
        conn.connect()

        try {
            if (conn.responseCode !in 200..299) {
                error("HTTP ${conn.responseCode} для $url")
            }
            return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
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
