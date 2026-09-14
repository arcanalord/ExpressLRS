package club.fpv.chatlite

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class ChatBackend {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    fun stream(
        backendUrl: String,
        proxyToken: String,
        model: String,
        messages: List<ChatMessage>,
    ): Flow<String> = callbackFlow {
        val endpoint = endpointFor(backendUrl)
        val payload = JSONObject().apply {
            put("model", model)
            put("messages", JSONArray().apply {
                messages.forEach { message ->
                    put(JSONObject().put("role", message.role).put("content", message.content))
                }
            })
        }

        val requestBuilder = Request.Builder()
            .url(endpoint)
            .post(payload.toString().toRequestBody(JSON))
            .header("Accept", "text/plain")
            .header("Cache-Control", "no-cache")

        if (proxyToken.isNotBlank()) {
            requestBuilder.header("Authorization", "Bearer $proxyToken")
        }

        val call = client.newCall(requestBuilder.build())
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (call.isCanceled()) close() else close(e)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use { res ->
                    if (!res.isSuccessful) {
                        val detail = runCatching { res.body.string().take(500) }.getOrDefault("")
                        close(IOException("HTTP ${res.code}: ${detail.ifBlank { res.message }}"))
                        return
                    }

                    val source = res.body.source()
                    val buffer = Buffer()
                    try {
                        while (!source.exhausted()) {
                            val read = source.read(buffer, 8192)
                            if (read <= 0) continue
                            val chunk = buffer.readUtf8()
                            if (chunk.isNotEmpty()) trySend(chunk)
                        }
                        close()
                    } catch (t: Throwable) {
                        if (call.isCanceled()) close() else close(t)
                    }
                }
            }
        })

        awaitClose { call.cancel() }
    }.buffer(Channel.UNLIMITED)

    private fun endpointFor(base: String): String {
        val clean = base.trim().trimEnd('/')
        require(clean.startsWith("https://")) { "Backend URL must start with https://" }
        return if (clean.endsWith("/api/chat")) clean else "$clean/api/chat"
    }

    private companion object {
        val JSON = "application/json; charset=utf-8".toMediaType()
    }
}
