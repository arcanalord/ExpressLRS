package com.arcanalord.service_studio

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
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
            val release = fetchReleaseInfo()
            val bundle = ensureBundle(release.commitSha)
            val root = JSONObject(readZipText(bundle, "firmware/hardware/targets.json"))

            val targets = mutableListOf<Map<String, Any?>>()
            collectTargets(
                node = root,
                path = mutableListOf(),
                stableVersion = release.version,
                out = targets,
            )
            targets.sortBy {
                (it["productName"]?.toString() ?: it["targetPath"]?.toString() ?: "")
                    .lowercase()
            }

            mapOf(
                "status" to "ok",
                "version" to release.version,
                "releaseName" to release.releaseName,
                "publishedAt" to release.publishedAt,
                "commitSha" to release.commitSha,
                "source" to "ExpressLRS pinned firmware bundle",
                "hardwarePinned" to true,
                "targetCount" to targets.size,
                "targets" to targets,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось загрузить version-pinned каталог ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
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
                "message" to "Не удалось проверить version-pinned target ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    fun prepareFirmware(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
        regulatoryProfile: String,
        bindingPhrase: String?,
        wifiSsid: String?,
        wifiPassword: String?,
        autoWifiSeconds: Int?,
        rxBaud: Int?,
        lockOnFirstConnection: Boolean?,
    ): Map<String, Any?> {
        return try {
            val catalog = fetchCatalogInternal(
                targetPath = targetPath,
                expectedProductName = expectedProductName,
                expectedPlatform = expectedPlatform,
                expectedFirmware = expectedFirmware,
            )
            validateStudioPreparation(catalog)

            val allowedRegions = regulatoryOptions(catalog.category)
            if (!allowedRegions.contains(regulatoryProfile)) {
                error("Радиорегион $regulatoryProfile не подходит для ${catalog.category}")
            }
            if ((!wifiSsid.isNullOrBlank() || !wifiPassword.isNullOrBlank() || autoWifiSeconds != null) &&
                !catalog.uploadMethods.contains("wifi")
            ) {
                error("Этот target не заявляет поддержку Wi-Fi")
            }
            if (!wifiPassword.isNullOrBlank() && wifiSsid.isNullOrBlank()) {
                error("Пароль Wi-Fi задан без SSID")
            }

            val bundle = ensureBundle(catalog.commitSha)
            val target = fetchTargetFromBundle(bundle, targetPath)
            val cacheProfile = cacheFolderFor(catalog.category, regulatoryProfile)
            val generic = readZipBytes(
                bundle,
                "firmware/$cacheProfile/${catalog.firmware}/firmware.bin",
            )

            val hwDir = if (catalog.category.startsWith("tx_")) "TX" else "RX"
            val layout = JSONObject(
                readZipText(
                    bundle,
                    "firmware/hardware/$hwDir/${catalog.layoutFile}",
                )
            )

            val overlay = target.optJSONObject("overlay")
            if (overlay != null) {
                val keys = overlay.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    layout.put(key, overlay.get(key))
                }
            }

            val options = buildUnifiedOptions(
                category = catalog.category,
                regulatoryProfile = regulatoryProfile,
                bindingPhrase = bindingPhrase,
                wifiSsid = wifiSsid,
                wifiPassword = wifiPassword,
                autoWifiSeconds = autoWifiSeconds,
                rxBaud = rxBaud,
                lockOnFirstConnection = lockOnFirstConnection,
            )

            val configured = configureUnifiedEspFirmware(
                source = generic,
                productName = catalog.productName,
                luaName = catalog.luaName,
                layoutJson = layout.toString(),
                priorTargetName = catalog.priorTargetName,
                optionsJson = options.toString(),
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
                .put("hardwareSource", "same firmware.zip commit")
                .put("targetPath", catalog.targetPath)
                .put("productName", catalog.productName)
                .put("platform", catalog.platform)
                .put("firmware", catalog.firmware)
                .put("regulatoryProfile", regulatoryProfile)
                .put("writeOffset", "0x0")
                .put("fileName", out.name)
                .put("fileSize", out.length())
                .put("sha256", firmwareSha256)
                .put("bindingPhraseSet", !bindingPhrase.isNullOrBlank())
                .put("wifiConfigured", !wifiSsid.isNullOrBlank())
                .put("rxBaud", rxBaud ?: JSONObject.NULL)
                .put("lockOnFirstConnection", lockOnFirstConnection ?: JSONObject.NULL)
            val manifestFile = File(dir, "manifest.json")
            manifestFile.writeText(manifest.toString(2), Charsets.UTF_8)

            mapOf(
                "status" to "prepared",
                "message" to "Version-pinned прошивка ExpressLRS подготовлена для ${catalog.productName}",
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
                "hardwarePinned" to true,
                "readyToFlash" to true,
            )
        } catch (e: Exception) {
            mapOf(
                "status" to "error",
                "message" to "Не удалось подготовить прошивку ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    private fun fetchReleaseInfo(): ReleaseInfo {
        val release = JSONObject(httpGetText(RELEASES_LATEST))
        val tag = release.getString("tag_name")
        val releaseName = release.optString("name", tag)
        val publishedAt = release.optString("published_at").ifBlank { null }
        val commit = JSONObject(
            httpGetText(COMMITS_API + URLEncoder.encode(tag, "UTF-8"))
        )
        return ReleaseInfo(
            version = tag,
            releaseName = releaseName,
            publishedAt = publishedAt,
            commitSha = commit.getString("sha"),
        )
    }

    private fun ensureBundle(commitSha: String): File {
        val dir = File(context.cacheDir, "elrs-bundles")
        if (!dir.exists() && !dir.mkdirs()) error("Не удалось создать cache каталога")
        val file = File(dir, "$commitSha-firmware.zip")
        if (file.isFile && file.length() > 1024 * 1024) return file

        val tmp = File(dir, "$commitSha-firmware.zip.part")
        if (tmp.exists()) tmp.delete()

        val conn = open("$CACHE_BASE/$commitSha/firmware.zip")
        conn.connectTimeout = 15000
        conn.readTimeout = 90000
        conn.connect()
        try {
            if (conn.responseCode !in 200..299) {
                error("официальный firmware bundle HTTP ${conn.responseCode}")
            }
            conn.inputStream.use { input ->
                tmp.outputStream().use { output -> input.copyTo(output) }
            }
        } finally {
            conn.disconnect()
        }

        if (tmp.length() < 1024 * 1024) {
            tmp.delete()
            error("получен слишком маленький firmware bundle")
        }
        if (!tmp.renameTo(file)) {
            tmp.copyTo(file, overwrite = true)
            tmp.delete()
        }
        return file
    }

    private fun collectTargets(
        node: JSONObject,
        path: MutableList<String>,
        stableVersion: String,
        out: MutableList<Map<String, Any?>>,
    ) {
        if (node.has("product_name") && node.has("platform") && node.has("firmware")) {
            val targetPath = path.joinToString(".")
            val category = path.getOrNull(1).orEmpty()
            val methods = jsonStringList(node.optJSONArray("upload_methods"))
            val features = jsonStringList(node.optJSONArray("features"))
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
                    stableCompatible &&
                    regulatoryOptions(category).isNotEmpty()

            out += mapOf(
                "targetPath" to targetPath,
                "vendor" to (path.firstOrNull() ?: ""),
                "category" to category,
                "role" to if (category.startsWith("rx_")) "RX" else if (category.startsWith("tx_")) "TX" else "",
                "band" to bandLabel(category),
                "productName" to node.optString("product_name", targetPath),
                "luaName" to node.optString("lua_name").ifBlank { null },
                "platform" to platform,
                "firmware" to firmware,
                "layoutFile" to node.optString("layout_file").ifBlank { null },
                "minVersion" to minVersion,
                "uploadMethods" to methods,
                "priorTargetName" to node.optString("prior_target_name").ifBlank { null },
                "features" to features,
                "regulatoryOptions" to regulatoryOptions(category),
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
        val release = fetchReleaseInfo()
        val bundle = ensureBundle(release.commitSha)
        val target = fetchTargetFromBundle(bundle, targetPath)
        val category = targetPath.split('.').getOrNull(1).orEmpty()

        val product = target.getString("product_name")
        val platform = target.getString("platform")
        val firmware = target.getString("firmware")

        if (product != expectedProductName) {
            error("Target изменился: ожидался «$expectedProductName», получен «$product»")
        }
        if (platform != expectedPlatform) {
            error("Платформа изменилась: ожидалась $expectedPlatform, получена $platform")
        }
        if (firmware != expectedFirmware) {
            error("Семейство прошивки изменилось: ожидалось $expectedFirmware, получено $firmware")
        }

        val methods = jsonStringList(target.optJSONArray("upload_methods"))
        if (!methods.contains("uart")) error("Target не разрешает UART")

        val minVersion = target.optString("min_version").ifBlank { null }
        if (minVersion != null && !versionAtLeast(release.version, minVersion)) {
            error("Target требует ExpressLRS $minVersion или новее")
        }

        return Catalog(
            version = release.version,
            releaseName = release.releaseName,
            publishedAt = release.publishedAt,
            commitSha = release.commitSha,
            targetPath = targetPath,
            category = category,
            productName = product,
            luaName = target.optString("lua_name", product.take(16)),
            platform = platform,
            firmware = firmware,
            layoutFile = target.getString("layout_file"),
            minVersion = minVersion,
            uploadMethods = methods,
            priorTargetName = target.optString("prior_target_name").ifBlank { null },
            features = jsonStringList(target.optJSONArray("features")),
        )
    }

    private fun fetchTargetFromBundle(bundle: File, targetPath: String): JSONObject {
        var node = JSONObject(readZipText(bundle, "firmware/hardware/targets.json"))
        for (part in targetPath.split('.')) node = node.getJSONObject(part)
        return node
    }

    private fun readZipText(bundle: File, path: String): String =
        String(readZipBytes(bundle, path), Charsets.UTF_8)

    private fun readZipBytes(bundle: File, path: String): ByteArray {
        ZipFile(bundle).use { zip ->
            val normalized = path.removePrefix("./")
            val entry = zip.getEntry(normalized)
                ?: zip.entries().asSequence().firstOrNull {
                    it.name.removePrefix("./") == normalized
                }
                ?: error("В version-pinned bundle не найден $normalized")
            return zip.getInputStream(entry).use { it.readBytes() }
        }
    }

    private fun validateTargetPath(targetPath: String) {
        val parts = targetPath.split('.')
        if (parts.size < 3 || parts.any { !it.matches(Regex("[A-Za-z0-9_-]+")) }) {
            error("Некорректный путь target: $targetPath")
        }
    }

    private fun validateStudioPreparation(catalog: Catalog) {
        if (catalog.platform != "esp8285") {
            error("Подготовка для ${catalog.platform} пока не включена")
        }
        if (!catalog.firmware.startsWith(EXPECTED_FIRMWARE_8285_PREFIX)) {
            error("Семейство ${catalog.firmware} пока не включено")
        }
        if (!catalog.category.startsWith("rx_")) {
            error("alpha.10 автоматически готовит только RX")
        }
    }

    private fun bandLabel(category: String): String = when {
        category.contains("2400") -> "2.4 ГГц"
        category.contains("900") -> "900 МГц"
        category.contains("433") -> "433 МГц"
        category.contains("dual") -> "Dual Band"
        else -> ""
    }

    private fun regulatoryOptions(category: String): List<String> = when {
        category.contains("2400") -> listOf("FCC", "LBT")
        category.contains("900") -> listOf("FCC_915", "EU_868", "AU_915", "IN_866")
        category.contains("433") -> listOf("US_433", "US_433_WIDE", "EU_433", "AU_433")
        else -> emptyList()
    }

    private fun cacheFolderFor(category: String, regulatoryProfile: String): String {
        return if (category.contains("2400") && regulatoryProfile == "LBT") {
            "LBT"
        } else {
            "FCC"
        }
    }

    private fun buildUnifiedOptions(
        category: String,
        regulatoryProfile: String,
        bindingPhrase: String?,
        wifiSsid: String?,
        wifiPassword: String?,
        autoWifiSeconds: Int?,
        rxBaud: Int?,
        lockOnFirstConnection: Boolean?,
    ): JSONObject {
        val flags = JSONObject()
        if (!bindingPhrase.isNullOrBlank()) {
            flags.put("uid", JSONArray(generateUid(bindingPhrase).map { it.toInt() and 0xFF }))
        }
        if (!wifiSsid.isNullOrBlank()) flags.put("wifi-ssid", wifiSsid)
        if (!wifiPassword.isNullOrBlank() && !wifiSsid.isNullOrBlank()) {
            flags.put("wifi-password", wifiPassword)
        }
        if (autoWifiSeconds != null) flags.put("wifi-on-interval", autoWifiSeconds)
        if (rxBaud != null) flags.put("rcvr-uart-baud", rxBaud)
        if (lockOnFirstConnection != null) {
            flags.put("lock-on-first-connection", lockOnFirstConnection)
        }

        domainNumber(regulatoryProfile)?.let { flags.put("domain", it) }
        flags.put(
            "flash-discriminator",
            SecureRandom().nextInt().toLong() and 0xFFFFFFFFL,
        )
        return flags
    }

    private fun generateUid(phrase: String): ByteArray {
        val csv = phrase.split(',').mapNotNull { it.trim().toIntOrNull() }
        if (csv.size in 4..6 && csv.all { it in 0..255 } &&
            phrase.split(',').size == csv.size
        ) {
            val out = ByteArray(6)
            val start = 6 - csv.size
            csv.forEachIndexed { index, value -> out[start + index] = value.toByte() }
            return out
        }
        return MessageDigest.getInstance("MD5")
            .digest("-DMY_BINDING_PHRASE=\"$phrase\"".toByteArray(Charsets.UTF_8))
            .copyOfRange(0, 6)
    }

    private fun domainNumber(profile: String): Int? = when (profile) {
        "AU_915" -> 0
        "FCC_915" -> 1
        "EU_868" -> 2
        "IN_866" -> 3
        "AU_433" -> 4
        "EU_433" -> 5
        "US_433" -> 6
        "US_433_WIDE" -> 7
        else -> null
    }

    private fun jsonStringList(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return List(array.length()) { i -> array.optString(i) }.filter { it.isNotBlank() }
    }

    private fun versionAtLeast(current: String, required: String): Boolean {
        fun parse(v: String): List<Int> {
            val parts = v.trim().removePrefix("v").split('.').take(3).map { part ->
                Regex("""\d+""").find(part)?.value?.toIntOrNull() ?: 0
            }
            return parts + List(maxOf(0, 3 - parts.size)) { 0 }
        }
        val a = parse(current)
        val b = parse(required)
        for (i in 0 until 3) {
            if (a[i] > b[i]) return true
            if (a[i] < b[i]) return false
        }
        return true
    }

    private fun configureUnifiedEspFirmware(
        source: ByteArray,
        productName: String,
        luaName: String,
        layoutJson: String,
        priorTargetName: String?,
        optionsJson: String,
    ): ByteArray {
        val end = findFirmwareEnd(source)
        if (end <= 0 || end > source.size) {
            error("не удалось определить конец ESP firmware image")
        }

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
        pos = writeFixed(configured, pos, optionsJson.toByteArray(Charsets.UTF_8), 512)
        pos = writeFixed(configured, pos, layoutJson.toByteArray(Charsets.UTF_8), 2048)

        if (priorBytes.isNotEmpty()) {
            priorBytes.copyInto(configured, destinationOffset = pos)
        }
        return configured
    }

    private fun findFirmwareEnd(bytes: ByteArray): Int {
        fun u8(i: Int) = bytes[i].toInt() and 0xFF
        fun le32(i: Int): Int =
            u8(i) or (u8(i + 1) shl 8) or (u8(i + 2) shl 16) or (u8(i + 3) shl 24)

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
            if (size < 0 || pos + 8 + size > bytes.size) error("ESP segment outside image")
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
        data.copyInto(out, offset, 0, n)
        out.fill(0, offset + n, offset + size)
        return offset + size
    }

    private fun httpGetText(url: String): String {
        val conn = open(url)
        conn.connectTimeout = 12000
        conn.readTimeout = 20000
        conn.connect()
        try {
            if (conn.responseCode !in 200..299) error("HTTP ${conn.responseCode}")
            return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun open(url: String): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            setRequestProperty("User-Agent", "ESP-Service-Studio/0.10")
            setRequestProperty("Accept-Encoding", "identity")
            instanceFollowRedirects = true
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
}
