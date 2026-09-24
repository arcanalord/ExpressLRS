package org.fpvclub.mesh

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.FileInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.io.RandomAccessFile

class MapPlatformViewFactory(
    private val messenger: BinaryMessenger,
    private val packageStore: MapPackageStore,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        MapPlatformView(context, messenger, viewId, packageStore)
}

@SuppressLint("SetJavaScriptEnabled")
private class MapPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val packageStore: MapPackageStore,
) : PlatformView {
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "org.fpvclub.mesh/mapview/$viewId")
    private val webView = WebView(context)

    init {
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.cacheMode = WebSettings.LOAD_DEFAULT
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.addJavascriptInterface(JsBridge(), "MeshBridge")
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                val uri = request?.url ?: return null
                if (uri.scheme != "https" || uri.host != "app.local") return null
                return when {
                    uri.path?.startsWith("/assets/") == true ->
                        assetResponse(uri.path!!.removePrefix("/assets/"))
                    uri.path == "/offline/active.pmtiles" -> pmtilesResponse(request)
                    else -> WebResourceResponse(
                        "text/plain",
                        "utf-8",
                        404,
                        "Not Found",
                        emptyMap(),
                        "".byteInputStream(),
                    )
                }
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPoints" -> {
                    val json = call.argument<String>("json") ?: "[]"
                    eval("window.MeshMap && window.MeshMap.setPoints($json)")
                    result.success(null)
                }
                "focus" -> {
                    val lat = call.argument<Double>("lat") ?: 0.0
                    val lon = call.argument<Double>("lon") ?: 0.0
                    val zoom = call.argument<Double>("zoom") ?: 15.0
                    eval("window.MeshMap && window.MeshMap.focus($lat,$lon,$zoom)")
                    result.success(null)
                }
                "reload" -> {
                    webView.loadUrl(
                        "https://app.local/assets/index.html?reload=${System.currentTimeMillis()}",
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        webView.loadUrl("https://app.local/assets/index.html")
    }

    override fun getView() = webView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        webView.removeJavascriptInterface("MeshBridge")
        webView.destroy()
    }

    private fun eval(js: String) = main.post { webView.evaluateJavascript(js, null) }

    private fun assetResponse(relative: String): WebResourceResponse {
        val path = "flutter_assets/assets/map_runtime/$relative"
        return try {
            val input = webView.context.assets.open(path)
            val mime = when {
                relative.endsWith(".html") -> "text/html"
                relative.endsWith(".css") -> "text/css"
                relative.endsWith(".js") || relative.endsWith(".mjs") -> "text/javascript"
                relative.endsWith(".json") -> "application/json"
                else -> "application/octet-stream"
            }
            WebResourceResponse(mime, "utf-8", input)
        } catch (_: Throwable) {
            WebResourceResponse(
                "text/plain",
                "utf-8",
                404,
                "Not Found",
                emptyMap(),
                "".byteInputStream(),
            )
        }
    }

    private fun pmtilesResponse(request: WebResourceRequest): WebResourceResponse {
        val file = packageStore.activeFile()
            ?: return WebResourceResponse(
                "text/plain",
                "utf-8",
                404,
                "No Map",
                emptyMap(),
                "".byteInputStream(),
            )
        val total = file.length()
        val range = request.requestHeaders["Range"] ?: request.requestHeaders["range"]
        if (range == null || !range.startsWith("bytes=")) {
            return WebResourceResponse(
                "application/vnd.pmtiles",
                null,
                200,
                "OK",
                mapOf("Content-Length" to total.toString(), "Accept-Ranges" to "bytes"),
                FileInputStream(file),
            )
        }
        val spec = range.removePrefix("bytes=").substringBefore(',')
        val parts = spec.split('-', limit = 2)
        val start = parts.getOrNull(0)?.toLongOrNull() ?: 0L
        val requestedEnd = parts.getOrNull(1)?.toLongOrNull()
        if (start < 0 || start >= total) {
            return WebResourceResponse(
                "application/vnd.pmtiles",
                null,
                416,
                "Range Not Satisfiable",
                mapOf("Content-Range" to "bytes */$total"),
                "".byteInputStream(),
            )
        }
        val end = (requestedEnd ?: (total - 1)).coerceAtMost(total - 1).coerceAtLeast(start)
        val length = end - start + 1
        val stream = FileInputStream(file)
        var skipped = 0L
        while (skipped < start) {
            val step = stream.skip(start - skipped)
            if (step <= 0) break
            skipped += step
        }
        return WebResourceResponse(
            "application/vnd.pmtiles",
            null,
            206,
            "Partial Content",
            mapOf(
                "Content-Range" to "bytes $start-$end/$total",
                "Content-Length" to length.toString(),
                "Accept-Ranges" to "bytes",
                "Cache-Control" to "no-store",
            ),
            LimitedInputStream(stream, length),
        )
    }

    inner class JsBridge {
        @JavascriptInterface
        fun sourceMode(): String = packageStore.sourceMode()

        @JavascriptInterface
        fun readPmtiles(offsetText: String, lengthText: String): String {
            val file = packageStore.activeFile() ?: return ""
            val offset = offsetText.toLongOrNull() ?: return ""
            val requested = lengthText.toIntOrNull() ?: return ""
            if (offset < 0 || requested <= 0 || offset >= file.length()) return ""
            val length = minOf(requested.toLong(), file.length() - offset).toInt()
            if (length <= 0) return ""
            val bytes = ByteArray(length)
            RandomAccessFile(file, "r").use { input ->
                input.seek(offset)
                input.readFully(bytes)
            }
            return Base64.encodeToString(bytes, Base64.NO_WRAP)
        }

        @JavascriptInterface
        fun onMapReady() {
            main.post { channel.invokeMethod("mapReady", null) }
        }

        @JavascriptInterface
        fun onMapTap(lat: Double, lon: Double) {
            main.post {
                channel.invokeMethod("mapTap", mapOf("lat" to lat, "lon" to lon))
            }
        }
    }
}

private class LimitedInputStream(
    input: InputStream,
    private var remaining: Long,
) : FilterInputStream(input) {
    override fun read(): Int {
        if (remaining <= 0) return -1
        val value = super.read()
        if (value >= 0) remaining--
        return value
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (remaining <= 0) return -1
        val count = super.read(buffer, offset, minOf(length.toLong(), remaining).toInt())
        if (count > 0) remaining -= count.toLong()
        return count
    }
}