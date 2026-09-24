package org.fpvclub.mesh

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream

class MapPackageStore(private val context: Context) {
    private val dir: File
        get() = File(context.filesDir, "mesh-messenger/offline-maps").also { it.mkdirs() }
    private val prefs
        get() = context.getSharedPreferences("mesh-map-packages", Context.MODE_PRIVATE)

    fun list(): List<Map<String, Any>> {
        val selected = selectedId()
        val offline = sourceMode() == "offline"
        return dir.listFiles()
            ?.filter { it.isFile && it.extension.equals("pmtiles", ignoreCase = true) }
            ?.sortedBy { it.name.lowercase() }
            ?.map {
                mapOf(
                    "id" to it.name,
                    "name" to it.nameWithoutExtension,
                    "bytes" to it.length(),
                    "selected" to (it.name == selected),
                    "active" to (offline && it.name == selected),
                )
            } ?: emptyList()
    }

    fun sourceState(): Map<String, Any?> {
        val selected = selectedId()
        val selectedFile = selected?.let { File(dir, it) }?.takeIf { it.isFile }
        val hasOffline = dir.listFiles()?.any {
            it.isFile && it.extension.equals("pmtiles", ignoreCase = true)
        } == true
        val requested = prefs.getString("sourceMode", null)
        val mode = when {
            requested == "online" -> "online"
            requested == "offline" && selectedFile != null -> "offline"
            requested == "offline" -> "online"
            selectedFile != null -> "offline"
            else -> "online"
        }
        return mapOf(
            "mode" to mode,
            "selectedId" to selectedFile?.name,
            "hasOffline" to hasOffline,
        )
    }

    fun sourceMode(): String = sourceState()["mode"] as String

    fun setSourceMode(mode: String): Map<String, Any?> {
        require(mode == "online" || mode == "offline") { "MAP_SOURCE_MODE_INVALID" }
        if (mode == "offline") {
            val selected = selectedId()
            val file = selected?.let { File(dir, it) }
            require(file?.isFile == true) { "MAP_OFFLINE_NOT_SELECTED" }
        }
        prefs.edit().putString("sourceMode", mode).apply()
        return sourceState()
    }

    fun activeFile(): File? {
        if (sourceMode() != "offline") return null
        val name = selectedId() ?: return null
        val file = File(dir, name)
        return file.takeIf { it.isFile }
    }

    fun setActive(id: String?): Map<String, Any?> {
        if (id.isNullOrBlank()) {
            prefs.edit().remove("active").putString("sourceMode", "online").apply()
            return sourceState()
        }
        val safe = File(id).name
        val file = File(dir, safe)
        require(file.isFile && file.extension.equals("pmtiles", true)) {
            "MAP_PACKAGE_NOT_FOUND"
        }
        prefs.edit()
            .putString("active", safe)
            .putString("sourceMode", "offline")
            .apply()
        return sourceState()
    }

    fun delete(id: String): Boolean {
        val safe = File(id).name
        val file = File(dir, safe)
        val deleted = file.isFile && file.delete()
        if (deleted && selectedId() == safe) {
            prefs.edit().remove("active").putString("sourceMode", "online").apply()
        }
        return deleted
    }

    fun importUri(resolver: ContentResolver, uri: Uri): Map<String, Any> {
        val display = queryName(resolver, uri) ?: "map-${System.currentTimeMillis()}.pmtiles"
        var clean = display.replace(Regex("[^A-Za-z0-9._ -]"), "_").trim()
        if (!clean.lowercase().endsWith(".pmtiles")) clean += ".pmtiles"
        if (clean.length > 96) clean = clean.takeLast(96)
        var target = File(dir, clean)
        if (target.exists()) {
            target = File(dir, "${target.nameWithoutExtension}-${System.currentTimeMillis()}.pmtiles")
        }
        resolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "MAP_IMPORT_OPEN_FAILED" }
            FileOutputStream(target).use { out -> input.copyTo(out, 256 * 1024) }
        }
        try {
            validate(target)
        } catch (t: Throwable) {
            target.delete()
            throw t
        }
        prefs.edit()
            .putString("active", target.name)
            .putString("sourceMode", "offline")
            .apply()
        return mapOf(
            "id" to target.name,
            "name" to target.nameWithoutExtension,
            "bytes" to target.length(),
            "selected" to true,
            "active" to true,
        )
    }

    private fun selectedId(): String? {
        val name = prefs.getString("active", "") ?: ""
        return name.takeIf { it.isNotBlank() }
    }

    private fun validate(file: File) {
        require(file.length() >= 127) { "PMTILES_TOO_SMALL" }
        val magic = ByteArray(7)
        file.inputStream().use { input ->
            require(input.read(magic) == magic.size) { "PMTILES_HEADER_INVALID" }
        }
        require(String(magic, Charsets.US_ASCII) == "PMTiles") {
            "PMTILES_MAGIC_INVALID"
        }
    }

    private fun queryName(resolver: ContentResolver, uri: Uri): String? {
        resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
