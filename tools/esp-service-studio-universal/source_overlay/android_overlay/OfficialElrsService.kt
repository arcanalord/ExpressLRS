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
        private const val TARGETS_ENTRY =
            "firmware/hardware/targets.json"
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
        val targetsSha256: String,
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
            "targetsSha256" to targetsSha256,
            "hardwarePinned" to true,
        )
    }

    fun fetchCatalogIndex(): Map<String, Any?> {
        return try {
            val release = fetchReleaseInfo()
            val bundle = ensureBundle(release.commitSha)
            val targetsBytes = readZipBytes(bundle, TARGETS_ENTRY)
            val root = JSONObject(targetsBytes.toString(Charsets.UTF_8))
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
                "source" to "ExpressLRS firmware.zip / hardware",
                "targetCount" to targets.size,
                "targetsSha256" to sha256(targetsBytes),
                "hardwarePinned" to true,
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
                "message" to "Не удалось проверить target ExpressLRS: ${e.message ?: e.javaClass.simpleName}",
            )
        }
    }

    fun prepareFirmware(
        targetPath: String,
        expectedProductName: String,
        expectedPlatform: String,
        expectedFirmware: String,
        regulatoryDomain: String,
        bindingPhrase: String?,
        wifiSsid: String?,
        wifiPassword: String?,
        autoWifiSeconds: Int?,
        lockOnFirstConnection: Boolean,
        rxUartBaud: Int?,
    ): Map<String, Any?> {
        return try {
            val catalog = fetchCatalogInternal(
                targetPath = targetPath,
                expectedProductName = expectedProductName,
                expectedPlatform = expectedPlatform,
                expectedFirmware = expectedFirmware,
            )
            validateStudioPreparation(catalog)
            validateRegulatoryDomain(catalog.category, regulatoryDomain)

            val releaseBundle = ensureBundle(catalog.commitSha)
            val target = fetchTargetFromBundle(releaseBundle, targetPath)
            val artifactBucket = artifactBucket(
                category = catalog.category,
                regulatoryDomain = regulatoryDomain,
            )

            val firmwareEntry =
                "firmware/$artifactBucket/${catalog.firmware}/firmware.bin"
            val generic = readZipBytes(releaseBundle, firmwareEntry)

            val hwDir = if (catalog.category.startsWith("tx_")) "TX" else "RX"
            val layoutEntry =
                "firmware/hardware/$hwDir/${catalog.layoutFile}"
            val layoutBytes = readZipBytes(releaseBundle, layoutEntry)
            val layout = JSONObject(layoutBytes.toString(Charsets.UTF_8))

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
                regulatoryDomain = regulatoryDomain,
                bindingPhrase = bindingPhrase,
                wifiSsid = wifiSsid,
                wifiPassword = wifiPassword,
                autoWifiSeconds = autoWifiSeconds,
                lockOnFirstConnection = lockOnFirstConnection,
                rxUartBaud = rxUartBaud,
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
                "firmware/elrs/${catalog.version}/$targetSlug/$regulatoryDomain",
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
                .put("category", catalog.category)
                .put("regulatoryDomain", regulatoryDomain)
                .put("writeOffset", "0x0")
                .put("fileName", out.name)
                .put("fileSize", out.length())
                .put("sha256", firmwareSha256)
                .put("targetsSha256", catalog.targetsSha256)
                .put("layoutSha256", sha256(layoutBytes))
                .put("artifactBucket", artifactBucket)
            val manifestFile = File(dir, "manifest.json")
            manifestFile.writeText(manifest.toString(2), Charsets.UTF_8)

            mapOf(
                "status" to "prepared",
                "message" to "Официальная прошивка ExpressLRS подготовлена из одного version-pinned bundle",
                "version" to catalog.version,
                "releaseName" to catalog.releaseName,
                "commitSha" to catalog.commitSha,
                "targetPath" to catalog.targetPath,
                "productName" to catalog.productName,
                "platform" to catalog.platform,
                "firmware" to catalog.firmware,
                "regulatoryDomain" to regulatoryDomain,
                "writeOffset" to "0x0",
                "filePath" to out.absolutePath,
                "fileSize" to out.length(),
                "sha256" to firmwareSha256,
                "manifestPath" to manifestFile.absolutePath,
                "targetsSha256" to catalog.targetsSha256,
                "layoutSha256" to sha256(layoutBytes),
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
            httpGetText(COMMITS_API + urlEncode(tag))
        )
        return ReleaseInfo(
            version = tag,
            releaseName = releaseName,
            publishedAt = publishedAt,
            commitSha = commit.getString("sha"),
        )
    }

    private fun ensureBundle(commitSha: String): File {
        if (!commitSha.matches(Regex("[0-9a-fA-F]{40}"))) {
            error("Некорректный commit SHA ExpressLRS")
        }

        val dir = File(context.cacheDir, "elrs/$commitSha")
        if (!dir.exists() && !dir.mkdirs()) {
            error("Не удалось создать cache ExpressLRS")
        }

        val bundle = File(dir, "firmware.zip")
        if (bundle.isFile && bundle.length() > 1024 * 1024) {
            return bundle
        }

        val tmp = File(dir, "firmware.zip.part")
        if (tmp.exists()) tmp.delete()

        val url = "$CACHE_BASE/$commitSha/firmware.zip"
        val conn = open(url)
        conn.connectTimeout = 15000
        conn.readTimeout = 120000
        conn.connect()

        try {
            if (conn.responseCode !in 200..299) {
                error("official firmware bundle HTTP ${conn.responseCode}")
            }
            tmp.outputStream().buffered().use { out ->
                conn.inputStream.buffered().use { input ->
                    input.copyTo(out, bufferSize = 128 * 1024)
                }
            }
        } finally {
            conn.disconnect()
        }

        if (tmp.length() < 1024 * 1024) {
            tmp.delete()
            error("Получен слишком маленький firmware.zip")
        }
        if (!tmp.renameTo(bundle)) {
            tmp.copyTo(bundle, overwrite = true)
            tmp.delete()
        }

        // Fail early if hardware metadata is missing from this exact bundle.
        readZipBytes(bundle, TARGETS_ENTRY)
        return bundle
    }

    private fun readZipBytes(zipFile: File, entryName: String): ByteArray {
        ZipFile(zipFile).use { zip ->
            val entry = zip.getEntry(entryName)
                ?: error("В version-pinned firmware.zip нет $entryName")
            if (entry.isDirectory) error("$entryName является каталогом")
            return zip.getInputStream(entry).use { it.readBytes() }
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
            val methods = jsonStringList(node.optJSONArray("upload_methods"))
            val features = jsonStringList(node.optJSONArray("features"))
            val category = path.getOrNull(1).orEmpty()
            val platform = node.optString("platform")
            val firmware = node.optString("firmware")
            val minVersion = node.optString("min_version").ifBlank { null }
            val stableCompatible =
                minVersion == null || versionAtLeast(stableVersion, minVersion)
            val supportsUart = methods.contains("uart")
            val domainOptions = regulatoryOptions(category)
            val studioSupported =
                platform == "esp8285" &&
                    firmware.startsWith(EXPECTED_FIRMWARE_8285_PREFIX) &&
                    category.startsWith("rx_") &&
                    category != "rx_dual" &&
                    supportsUart &&
                    stableCompatible &&
                    domainOptions.isNotEmpty()

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
                    category.contains("900") -> "Sub-GHz"
                    category.contains("dual") -> "Dual-band"
                    else -> ""
                },
                "productName" to node.optString("product_name", targetPath),
                "luaName" to node.optString("lua_name").ifBlank { null },
                "platform" to platform,
                "firmware" to firmware,
                "layoutFile" to node.optString("layout_file").ifBlank { null },
                "minVersion" to minVersion,
                "uploadMethods" to methods,
                "features" to features,
                "priorTargetName" to node.optString("prior_target_name").ifBlank { null },
                "stableCompatible" to stableCompatible,
                "supportsUart" to supportsUart,
                "studioSupported" to studioSupported,
                "regulatoryOptions" to domainOptions,
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
        val targetsBytes = readZipBytes(bundle, TARGETS_ENTRY)
        val root = JSONObject(targetsBytes.toString(Charsets.UTF_8))
        val target = findTarget(root, targetPath)

        val product = target.getString("product_name")
        val platform = target.getString("platform")
        val firmware = target.getString("firmware")
        val category = targetPath.split('.').getOrNull(1).orEmpty()

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
        if (!methods.contains("uart")) {
            error("Этот target не разрешает UART")
        }

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
            targetsSha256 = sha256(targetsBytes),
        )
    }

    private fun fetchTargetFromBundle(bundle: File, targetPath: String): JSONObject {
        val root = JSONObject(
            readZipBytes(bundle, TARGETS_ENTRY).toString(Charsets.UTF_8)
        )
        return findTarget(root, targetPath)
    }

    private fun findTarget(root: JSONObject, targetPath: String): JSONObject {
        var node = root
        for (part in targetPath.split('.')) {
            node = node.getJSONObject(part)
        }
        return node
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
        if (catalog.category == "rx_dual") {
            error("Dual-band пока не включён в безопасный alpha.10 путь")
        }
    }

    private fun regulatoryOptions(category: String): List<String> {
        return when (category) {
            "rx_2400", "tx_2400" -> listOf(
                "ISM_2400",
                "EU_CE_2400",
            )
            "rx_900", "tx_900" -> listOf(
                "FCC_915",
                "AU_915",
                "EU_868",
                "IN_866",
                "AU_433",
                "EU_433",
                "US_433",
                "US_433_WIDE",
            )
            else -> emptyList()
        }
    }

    private fun validateRegulatoryDomain(category: String, domain: String) {
        if (!regulatoryOptions(category).contains(domain)) {
            error("Регион $domain не подходит для $category")
        }
    }

    private fun artifactBucket(
        category: String,
        regulatoryDomain: String,
    ): String {
        return when {
            category.contains("2400") &&
                regulatoryDomain == "EU_CE_2400" -> "LBT"
            category.contains("2400") &&
                regulatoryDomain == "ISM_2400" -> "FCC"
            category.contains("900") -> "FCC"
            else -> error("Не поддержан artifact bucket для $category/$regulatoryDomain")
        }
    }

    private fun buildUnifiedOptions(
        category: String,
        regulatoryDomain: String,
        bindingPhrase: String?,
        wifiSsid: String?,
        wifiPassword: String?,
        autoWifiSeconds: Int?,
        lockOnFirstConnection: Boolean,
        rxUartBaud: Int?,
    ): JSONObject {
        val options = JSONObject()

        if (!bindingPhrase.isNullOrBlank()) {
            options.put("uid", JSONArray(generateUid(bindingPhrase.trim()).toList()))
        }

        if (!wifiSsid.isNullOrBlank()) {
            options.put("wifi-ssid", wifiSsid)
            if (!wifiPassword.isNullOrEmpty()) {
                options.put("wifi-password", wifiPassword)
            }
        }

        if (autoWifiSeconds != null) {
            if (autoWifiSeconds !in 10..3600) {
                error("Auto Wi-Fi должен быть от 10 до 3600 секунд")
            }
            options.put("wifi-on-interval", autoWifiSeconds)
        }

        if (lockOnFirstConnection) {
            options.put("lock-on-first-connection", true)
        }

        if (rxUartBaud != null) {
            if (rxUartBaud !in 1200..5000000) {
                error("Некорректный RX UART baud")
            }
            options.put("rcvr-uart-baud", rxUartBaud)
        }

        if (category.contains("900")) {
            options.put("domain", subGhzDomainNumber(regulatoryDomain))
        }

        options.put(
            "flash-discriminator",
            SecureRandom().nextInt().toLong() and 0xFFFFFFFFL,
        )
        return options
    }

    private fun generateUid(phrase: String): ByteArray {
        val commaValues = phrase.split(',').map { it.trim() }
        if (commaValues.size in 4..6) {
            val parsed = commaValues.map { it.toIntOrNull() }
            if (parsed.all { it != null && it in 0..255 }) {
                val values = parsed.map { it!! }.toMutableList()
                while (values.size < 6) values.add(0, 0)
                return ByteArray(6) { values[it].toByte() }
            }
        }

        return MessageDigest.getInstance("MD5")
            .digest("-DMY_BINDING_PHRASE=\"$phrase\"".toByteArray(Charsets.UTF_8))
            .copyOfRange(0, 6)
    }

    private fun subGhzDomainNumber(domain: String): Int {
        return when (domain) {
            "AU_915" -> 0
            "FCC_915" -> 1
            "EU_868" -> 2
            "IN_866" -> 3
            "AU_433" -> 4
            "EU_433" -> 5
            "US_433" -> 6
            "US_433_WIDE" -> 7
            else -> error("Неизвестный Sub-GHz domain: $domain")
        }
    }

    private fun jsonStringList(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return buildList {
            for (i in 0 until array.length()) {
                val value = array.optString(i)
                if (value.isNotBlank()) add(value)
            }
        }
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
            error("Не удалось определить конец ESP firmware image")
        }

        val optionsBytes = optionsJson.toByteArray(Charsets.UTF_8)
        if (optionsBytes.size > 512) {
            error("Параметры прошивки превышают 512 байт")
        }

        val layoutBytes = layoutJson.toByteArray(Charsets.UTF_8)
        if (layoutBytes.size > 2048) {
            error("Hardware layout превышает 2048 байт")
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
        pos = writeFixed(configured, pos, optionsBytes, 512)
        pos = writeFixed(configured, pos, layoutBytes, 2048)

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

    private fun httpGetText(url: String): String {
        val conn = open(url)
        conn.connectTimeout = 12000
        conn.readTimeout = 30000
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
            setRequestProperty("User-Agent", "ESP-Service-Studio/0.10")
            setRequestProperty("Accept-Encoding", "identity")
            instanceFollowRedirects = true
        }
    }

    private fun urlEncode(value: String): String {
        return java.net.URLEncoder.encode(value, "UTF-8")
    }

    private fun sha256(bytes: ByteArray): String {
        return MessageDigest
            .getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }
}
