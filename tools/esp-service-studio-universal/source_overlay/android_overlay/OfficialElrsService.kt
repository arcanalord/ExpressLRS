package com.arcanalord.service_studio

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.zip.ZipFile

class OfficialElrsService(private val context: Context) {
    companion object {
        private const val RELEASES_LATEST =
            "https://api.github.com/repos/ExpressLRS/ExpressLRS/releases/latest"
        private const val COMMITS_API =
            "https://api.github.com/repos/ExpressLRS/ExpressLRS/commits/"
        private const val CACHE_BASE =
            "https://artifactory.expresslrs.org/ExpressLRS"
        private const val EXPECTED_FIRMWARE_8285_PREFIX =
            "Unified_ESP8285_"
    }

    data class ReleaseInfo(
        val version: String,
        val releaseName: String,
        val publishedAt: String?,
        val commitSha: String,
    )

    data class Catalog(
        val version: String,
        val releaseName: String,
        val publishedAt: String?,
        val commitSha: String,
        val targetPath: String,
        val category: String,
        val productName: String,
        val luaName: String,
        val platform: String,
        val firmware: String,
        val layoutFile: String,
        val minVersion: String?,
        val uploadMethods: List<String>,
        val priorTargetName: String?,
        val features: List<String>,
    ) {
        fun asMap(): Map<String, Any?> = mapOf(
            "status" to "ok",
            "version" to version,
            "releaseName" to releaseName,
            "publishedAt" to publishedAt,
            "commitSha" to commitSha,
            "targetPath" to targetPath,
            "category" to category,
            "productName" to productName,
            "luaName" to luaName,
            "platform" to platform,
            "firmware" to firmware,
            "layoutFile" to layoutFile,
            "minVersion" to minVersion,
            "uploadMethods" to uploadMethods,
            "priorTargetName" to priorTargetName,
            "features" to features,
            "regulatoryOptions" to regulatoryOptions(category),
        )
    }

    fun fetchCatalogIndex(): Map<String, Any?> {
        return try {
            val release = JSONObject(httpGetText(RELEASES_LATEST))
            val tag = release.getString("tag_name")
            val releaseName = release.optString("name", tag)
            val publishedAt = release.optString("published_at").ifBlank { null }

            val commit = JSONObject(
                httpGetText(COMMITS_API + URLEncoder.encode(tag, "UTF-8"))
            )
            val sha = commit.getString("sha")

            val root = JSONObject(httpGetText(TARGETS_URL))
            val targets = mutableListOf<Map<String, Any?>>()
            collectTargets(
                node = root,
                path = mutableListOf(),
                stableVersion = tag,
                out = targets,
            )
            targets.sortBy {
                (it["productName"]?.toString() ?: it["targetPath"]?.toString() ?: "")
                    .lowercase()
            }

            mapOf(
                "status" to "ok",
                "version" to tag,
                "releaseName" to releaseName,
                "publishedAt" to publishedAt,
                "commitSha" to sha,
                "source" to "ExpressLRS/Targets",
                "targetCount" to targets.size,
                "targets" to targets,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось загрузить официальный каталог ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
                "targets" to emptyList<Map<String, Any?>>(),
            )
        }
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
                "message" to "Не удалось получить официальный target ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
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
            validateStudioPreparation(catalog)

            val target = fetchTarget(targetPath)
            val generic = downloadCachedFirmware(
                commitSha = catalog.commitSha,
                regulatoryProfile = regulatoryProfile,
                firmwareTarget = catalog.firmware,
            )

            val category = targetPath.split('.').getOrNull(1).orEmpty()
            val hwDir = if (category.startsWith("tx_")) "TX" else "RX"
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

            val firmwareSha256 = sha256(configured)
            val manifest = JSONObject()
                .put("version", catalog.version)
                .put("commitSha", catalog.commitSha)
                .put("targetPath", catalog.targetPath)
                .put("productName", catalog.productName)
                .put("platform", catalog.platform)
                .put("firmware", catalog.firmware)
                .put("regulatoryProfile", regulatoryProfile)
                .put("writeOffset", "0x0")
                .put("fileName", out.name)
                .put("fileSize", out.length())
                .put("sha256", firmwareSha256)
            val manifestFile = File(dir, "manifest.json")
            manifestFile.writeText(manifest.toString(2), Charsets.UTF_8)

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
                "sha256" to firmwareSha256,
                "manifestPath" to manifestFile.absolutePath,
                "readyToFlash" to true,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось подготовить прошивку ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    private fun collectTargets(
        node: JSONObject,
        path: MutableList<String>,
        stableVersion: String,
        out: MutableList<Map<String, Any?>>,
    ) {
        if (node.has("product_name") &&
            node.has("platform") &&
            node.has("firmware")
        ) {
            val targetPath = path.joinToString(".")
            val methods = mutableListOf<String>()
            val methodsArray = node.optJSONArray("upload_methods")
            if (methodsArray != null) {
                for (i in 0 until methodsArray.length()) {
                    methods += methodsArray.optString(i)
                }
            }

            val category = path.getOrNull(1).orEmpty()
            val platform = node.optString("platform")
            val firmware = node.optString("firmware")
            val minVersion = node.optString("min_version").ifBlank { null }
            val stableCompatible =
                minVersion == null || versionAtLeast(stableVersion, minVersion)
            val supportsUart = methods.contains("uart")
            val studioSupported =
                platform == "esp8285" &&
                    firmware.startsWith(EXPECTED_FIRMWARE_8285_PREFIX) &&
                    category.startsWith("rx_") &&
                    supportsUart &&
                    stableCompatible

            out += mapOf(
                "targetPath" to targetPath,
                "vendor" to (path.firstOrNull() ?: ""),
                "category" to category,
                "role" to when {
                    category.startsWith("rx_") -> "RX"
                    category.startsWith("tx_") -> "TX"
                    else -> ""
                },
                "band" to when {
                    category.contains("2400") -> "2.4 ГГц"
                    category.contains("900") -> "900 МГц"
                    else -> ""
                },
                "productName" to node.optString("product_name", targetPath),
                "luaName" to node.optString("lua_name").ifBlank { null },
                "platform" to platform,
                "firmware" to firmware,
                "layoutFile" to node.optString("layout_file").ifBlank { null },
                "minVersion" to minVersion,
                "uploadMethods" to methods,
                "priorTargetName" to node.optString("prior_target_name").ifBlank { null },
                "stableCompatible" to stableCompatible,
                "supportsUart" to supportsUart,
                "studioSupported" to studioSupported,
            )
            return
        }

        val keys = node.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val child = node.opt(key)
            if (child is JSONObject) {
                path.add(key)
                collectTargets(child, path, stableVersion, out)
                path.removeAt(path.lastIndex)
            }
        }
    }

    private fun fetchCatalogInternal(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
    ): Catalog {
        validateTargetPath(targetPath)

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
        val arr = target.optJSONArray("upload_methods")
        if (arr != null) {
            for (i in 0 until arr.length()) methods += arr.optString(i)
        }
        if (!methods.contains("uart")) {
            error("Официальный target не разрешает UART")
        }

        val minVersion = target.optString("min_version").ifBlank { null }
        if (minVersion != null && !versionAtLeast(tag, minVersion)) {
            error("Target требует ExpressLRS $minVersion или новее, stable сейчас $tag")
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
            minVersion = minVersion,
            uploadMethods = methods,
            priorTargetName = target.optString("prior_target_name").ifBlank { null },
        )
    }

    private fun validateTargetPath(targetPath: String) {
        val parts = targetPath.split('.')
        if (parts.size < 3 || parts.any { !it.matches(Regex("[A-Za-z0-9_-]+")) }) {
            error("Некорректный путь target: $targetPath")
        }
    }

    private fun validateStudioPreparation(catalog: Catalog) {
        if (catalog.platform != "esp8285") {
            error("Подготовка прошивки для ${catalog.platform} пока не включена")
        }
        if (!catalog.firmware.startsWith(EXPECTED_FIRMWARE_8285_PREFIX)) {
            error("Семейство ${catalog.firmware} пока не включено для автоматической подготовки")
        }
    }

    private fun versionAtLeast(current: String, required: String): Boolean {
        fun parse(v: String): List<Int> {
            val clean = v.trim().removePrefix("v")
            return clean.split('.').take(3).map { part ->
                Regex("""\d+""").find(part)?.value?.toIntOrNull() ?: 0
            }.let { parts ->
                parts + List(maxOf(0, 3 - parts.size)) { 0 }
            }
        }

        val a = parse(current)
        val b = parse(required)
        for (i in 0 until 3) {
            if (a[i] > b[i]) return true
            if (a[i] < b[i]) return false
        }
        return true
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
