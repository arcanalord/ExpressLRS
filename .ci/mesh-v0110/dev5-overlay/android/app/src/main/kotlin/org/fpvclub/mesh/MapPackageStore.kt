package org.fpvclub.mesh

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream

class MapPackageStore(private val context: Context) {
    private val dir: File get() = File(context.filesDir, "mesh-messenger/offline-maps").also { it.mkdirs() }
    private val prefs get() = context.getSharedPreferences("mesh-map-packages", Context.MODE_PRIVATE)

    fun list(): List<Map<String, Any>> {
        val active = prefs.getString("active", "") ?: ""
        return dir.listFiles()
            ?.filter { it.isFile && it.extension.equals("pmtiles", ignoreCase = true) }
            ?.sortedBy { it.name.lowercase() }
            ?.map {
                mapOf(
                    "id" to it.name,
                    "name" to it.nameWithoutExtension,
                    "bytes" to it.length(),
                    "active" to (it.name == active),
                )
            } ?: emptyList()
    }

    fun activeFile(): File? {
        val name = prefs.getString("active", "") ?: ""
        if (name.isBlank()) return null
        val file = File(dir, name)
        return file.takeIf { it.isFile }
    }

    fun setActive(id: String?): Map<String, Any?> {
        if (id.isNullOrBlank()) {
            prefs.edit().remove("active").apply()
            return mapOf("active" to null)
        }
        val safe = File(id).name
        val file = File(dir, safe)
        require(file.isFile && file.extension.equals("pmtiles", true)) { "MAP_PACKAGE_NOT_FOUND" }
        prefs.edit().putString("active", safe).apply()
        return mapOf("active" to safe, "bytes" to file.length())
    }

    fun delete(id: String): Boolean {
        val safe = File(id).name
        val file = File(dir, safe)
        val deleted = file.isFile && file.delete()
        if (deleted && prefs.getString("active", "") == safe) prefs.edit().remove("active").apply()
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
        prefs.edit().putString("active", target.name).apply()
        return mapOf(
            "id" to target.name,
            "name" to target.nameWithoutExtension,
            "bytes" to target.length(),
            "active" to true,
        )
    }

    private fun validate(file: File) {
        require(file.length() >= 127) { "PMTILES_TOO_SMALL" }
        val magic = ByteArray(7)
        file.inputStream().use { input ->
            require(input.read(magic) == magic.size) { "PMTILES_HEADER_INVALID" }
        }
        require(String(magic, Charsets.US_ASCII) == "PMTiles") { "PMTILES_MAGIC_INVALID" }
    }

    private fun queryName(resolver: ContentResolver, uri: Uri): String? {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
