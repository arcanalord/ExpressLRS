package club.fpv.chatlite

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

class ChatStore(context: Context) {
    private val historyFile = File(context.filesDir, "chat-lite-history.json")
    private val prefs = context.getSharedPreferences("chat-lite", Context.MODE_PRIVATE)

    fun loadMessages(): List<ChatMessage> = runCatching {
        if (!historyFile.exists()) {
            emptyList()
        } else {
            val array = JSONArray(historyFile.readText())
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    add(
                        ChatMessage(
                            id = o.optString("id").ifBlank { UUID.randomUUID().toString() },
                            role = o.optString("role", "assistant"),
                            content = o.optString("content"),
                            createdAt = o.optLong("createdAt", System.currentTimeMillis()),
                        )
                    )
                }
            }
        }
    }.getOrDefault(emptyList())

    fun saveMessages(messages: List<ChatMessage>) {
        val array = JSONArray()
        messages.forEach { message ->
            array.put(
                JSONObject()
                    .put("id", message.id)
                    .put("role", message.role)
                    .put("content", message.content)
                    .put("createdAt", message.createdAt)
            )
        }
        val tmp = File(historyFile.parentFile, historyFile.name + ".tmp")
        tmp.writeText(array.toString())
        if (!tmp.renameTo(historyFile)) {
            historyFile.writeText(array.toString())
            tmp.delete()
        }
    }

    fun clear() {
        historyFile.delete()
    }

    fun backendUrl(): String = prefs.getString("backend_url", "") ?: ""
    fun proxyToken(): String = prefs.getString("proxy_token", "") ?: ""
    fun model(): String = prefs.getString("model", DEFAULT_MODEL) ?: DEFAULT_MODEL

    fun saveConfig(backendUrl: String, proxyToken: String, model: String) {
        prefs.edit()
            .putString("backend_url", backendUrl.trim())
            .putString("proxy_token", proxyToken.trim())
            .putString("model", model.trim().ifBlank { DEFAULT_MODEL })
            .apply()
    }

    companion object {
        const val DEFAULT_MODEL = "openai/gpt-5.6-luna-fast"
    }
}
