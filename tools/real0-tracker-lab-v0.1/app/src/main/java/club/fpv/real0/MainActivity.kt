package club.fpv.real0

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : AppCompatActivity() {
    private val exec = Executors.newSingleThreadExecutor()
    private val tracker = NccTracker()
    private val videoBusy = AtomicBoolean(false)

    private lateinit var frameView: ImageView
    private lateinit var overlay: OverlayView
    private lateinit var status: TextView
    private lateinit var sourceLabel: TextView

    private var cameraProvider: ProcessCameraProvider? = null
    private var locked = false
    private var source = "NONE"
    @Volatile private var selectionFrozen = false
    @Volatile private var lastDisplayedFrame: Bitmap? = null
    @Volatile private var lastDisplayedTimestampNs: Long = 0L

    private var retriever: MediaMetadataRetriever? = null
    private var videoUs = 0L
    private var durationUs = 0L
    private var videoPlaying = false
    private val handler = Handler(Looper.getMainLooper())
    private var lastResult = TrackerResult(TrackState.IDLE, null, null, 0f, 0f, "")

    private val cameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        if (it) startCamera() else setStatus("Нет разрешения CAMERA")
    }

    private val openVideo = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) loadVideo(uri)
    }

    private val videoTick = object : Runnable {
        override fun run() {
            if (source == "VIDEO" && videoPlaying && !selectionFrozen) {
                requestVideoFrame(videoUs)
                videoUs = (videoUs + 100_000L).coerceAtMost(durationUs)
                if (videoUs >= durationUs) videoPlaying = false
            }
            handler.postDelayed(this, 100)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildUi()
        overlay.onQuickLock = { quickLockOnDisplayedFrame(it.x, it.y) }
        overlay.onPreciseLock = { lockOnDisplayedFrame(it) }
        handler.post(videoTick)
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply { setBackgroundColor(0xff07111b.toInt()) }
        frameView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.BLACK)
        }
        overlay = OverlayView(this)
        root.addView(frameView, FrameLayout.LayoutParams(-1, -1))
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(16))
            background = GradientDrawable().apply {
                setColor(0xee0b1724.toInt())
                cornerRadii = floatArrayOf(dp(20).toFloat(),dp(20).toFloat(),dp(20).toFloat(),dp(20).toFloat(),0f,0f,0f,0f)
            }
        }

        val top = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        sourceLabel = TextView(this).apply { setTextColor(0xffc7d5e1.toInt()); text = "SOURCE: NONE"; textSize = 13f }
        status = TextView(this).apply { setTextColor(Color.WHITE); text = "Выберите CAMERA или VIDEO"; textSize = 14f; setPadding(0,dp(4),0,dp(6)) }
        top.addView(sourceLabel, LinearLayout.LayoutParams(0, -2, 1f))
        top.addView(button("HELP") { showHelp() }, LinearLayout.LayoutParams(dp(72), dp(44)))
        panel.addView(top); panel.addView(status)

        val row1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row1.addView(button("CAMERA") { ensureCamera() }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row1.addView(button("VIDEO") { openVideo.launch(arrayOf("video/*")) }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row1.addView(button("RESET") { resetTracker() }, LinearLayout.LayoutParams(0, dp(52), 1f))
        panel.addView(row1)

        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row2.addView(button("QUICK LOCK") { armLock(true) }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row2.addView(button("PRECISE LOCK") { armLock(false) }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row2.addView(button("PLAY/PAUSE") {
            if (source == "VIDEO") {
                videoPlaying = !videoPlaying
                selectionFrozen = false
                setStatus(if (videoPlaying) "VIDEO PLAY" else "VIDEO PAUSE")
            }
        }, LinearLayout.LayoutParams(0, dp(52), 1f))
        panel.addView(row2)

        root.addView(panel, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(root)
    }

    private fun armLock(quick: Boolean) {
        if (source == "NONE" || lastDisplayedFrame == null) {
            setStatus("Сначала выберите источник и дождитесь кадра")
            return
        }
        if (source == "VIDEO") videoPlaying = false
        selectionFrozen = true
        if (quick) overlay.armQuick() else overlay.armPrecise()
        setStatus(if (quick) "Кадр заморожен — тапните по цели" else "Кадр заморожен — нарисуйте рамку цели")
    }

    private fun lockOnDisplayedFrame(r: RectF) {
        val frame = lastDisplayedFrame
        if (frame == null) {
            selectionFrozen = false
            setStatus("LOCK ERROR: нет отображённого кадра")
            return
        }
        setStatus("LOCK init...")
        exec.execute {
            tracker.init(frame, r, lastDisplayedTimestampNs)
            locked = true
            lastResult = TrackerResult(TrackState.TRACKING, r, r, 1f, 0f, "manual precise lock")
            selectionFrozen = false
            runOnUiThread {
                overlay.result = lastResult
                overlay.invalidate()
                status.text = "TRACKING q=1.00 | ${tracker.policy}"
            }
        }
    }

    private fun quickLockOnDisplayedFrame(x: Float, y: Float) {
        val frame = lastDisplayedFrame
        if (frame == null) {
            selectionFrozen = false
            setStatus("QUICK ERROR: нет отображённого кадра")
            return
        }
        setStatus("QUICK AutoFit...")
        exec.execute {
            lastResult = tracker.beginQuick(frame, x, y, lastDisplayedTimestampNs)
            locked = lastResult.state == TrackState.STABILIZING || lastResult.state == TrackState.TRACKING
            selectionFrozen = false
            runOnUiThread {
                overlay.result = lastResult
                overlay.invalidate()
                status.text = "${lastResult.state} q=${"%.2f".format(lastResult.quality)} A=${tracker.analysisWidth}px | ${lastResult.reason}"
            }
        }
    }

    private fun button(title: String, action: () -> Unit) = Button(this).apply {
        text = title; setAllCaps(false); setTextColor(Color.WHITE); textSize = 12f; gravity = Gravity.CENTER
        minHeight = dp(44); elevation = 0f; stateListAnimator = null
        background = GradientDrawable().apply { setColor(0xff162536.toInt()); cornerRadius = dp(14).toFloat() }
        setOnClickListener { action() }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun setStatus(message: String) { runOnUiThread { status.text = message } }

    private fun showHelp() {
        AlertDialog.Builder(this)
            .setTitle("Real-0 Tracker Lab v0.1.6 core candidate")
            .setMessage("""
                CAMERA — экран и трекер используют один кадр.
                VIDEO — локальный видеофайл.
                QUICK LOCK — тап задаёт точку; AutoFit подбирает рамку и подтверждает её несколько кадров.
                PRECISE LOCK — ручная рамка, контрольный режим.
                RESET — удалить захват.

                STABILIZING — QUICK LOCK ещё уточняет рамку.
                TRACKING — сопровождение.
                UNCERTAIN — уверенность снижена.
                LOST/SEARCHING — измеренная рамка скрыта, идёт полный повторный поиск.
                REACQUIRED — цель повторно подтверждена.
                Голубой пунктир — prediction.
            """.trimIndent())
            .setPositiveButton("OK", null).show()
    }

    private fun ensureCamera() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCamera()
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }

    private fun startCamera() {
        releaseVideo()
        source = "CAMERA"; sourceLabel.text = "SOURCE: CAMERA"; resetTracker(); setStatus("Запуск камеры...")
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            runCatching {
                val provider = future.get()
                cameraProvider = provider
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                analysis.setAnalyzer(exec) { image -> analyzeCamera(image) }
                provider.unbindAll()
                provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, analysis)
                setStatus("Камера готова. QUICK/PRECISE LOCK")
            }.onFailure { setStatus("CAMERA ERROR: ${it.message}") }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun analyzeCamera(image: ImageProxy) {
        try {
            if (source != "CAMERA" || selectionFrozen) return
            val bitmap = toBitmap(image)
            publishFrame(bitmap, runTracker = locked, timestampNs = image.imageInfo.timestamp)
        } catch (t: Throwable) {
            setStatus("CAMERA FRAME ERROR: ${t.message}")
        } finally {
            image.close()
        }
    }

    private fun loadVideo(uri: Uri) {
        cameraProvider?.unbindAll()
        runCatching {
            val r = MediaMetadataRetriever(); r.setDataSource(this, uri)
            retriever?.release(); retriever = r
            durationUs = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000L
            videoUs = 0L; source = "VIDEO"; sourceLabel.text = "SOURCE: VIDEO"; videoPlaying = false
            resetTracker(); requestVideoFrame(0L); setStatus("Видео загружено. LOCK, затем PLAY")
        }.onFailure { setStatus("VIDEO ERROR: ${it.message}") }
    }

    private fun requestVideoFrame(us: Long) {
        if (!videoBusy.compareAndSet(false, true)) return
        exec.execute {
            try {
                val r = retriever
                if (source == "VIDEO" && r != null && !selectionFrozen) {
                    val bm = runCatching { r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST) }
                        .getOrElse { setStatus("VIDEO FRAME ERROR: ${it.message}"); null }
                    if (bm != null && source == "VIDEO") publishFrame(bm, runTracker = locked, timestampNs = us * 1000L)
                }
            } finally { videoBusy.set(false) }
        }
    }

    private fun publishFrame(bitmap: Bitmap, runTracker: Boolean) {
        lastDisplayedFrame = bitmap
        overlay.frameW = bitmap.width; overlay.frameH = bitmap.height
        if (runTracker) lastResult = tracker.update(bitmap, timestampNs)
        runOnUiThread {
            frameView.setImageBitmap(bitmap)
            overlay.result = lastResult; overlay.invalidate()
            if (runTracker) status.text = "${lastResult.state} q=${"%.2f".format(lastResult.quality)} ${"%.1f".format(lastResult.processingMs)} ms A=${tracker.analysisWidth}px | ${tracker.policy}"
        }
    }

    private fun resetTracker() {
        locked = false; selectionFrozen = false; lastDisplayedTimestampNs = 0L; overlay.disarm(); tracker.reset()
        lastResult = TrackerResult(if (source == "NONE") TrackState.IDLE else TrackState.READY, null, null, 0f, 0f, "reset")
        overlay.result = lastResult; overlay.invalidate()
        setStatus(if (source == "NONE") "Выберите CAMERA или VIDEO" else "Готово. QUICK/PRECISE LOCK")
    }

    private fun releaseVideo() {
        videoPlaying = false; retriever?.release(); retriever = null; videoUs = 0L; durationUs = 0L
    }

    private fun toBitmap(image: ImageProxy): Bitmap {
        val plane = image.planes[0]
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        require(pixelStride == 4) { "Unexpected RGBA pixelStride=$pixelStride" }
        val rowPadding = rowStride - pixelStride * image.width
        val paddedWidth = image.width + rowPadding / pixelStride
        val padded = Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888)
        plane.buffer.rewind()
        padded.copyPixelsFromBuffer(plane.buffer)
        val cropped = if (paddedWidth == image.width) padded
        else Bitmap.createBitmap(padded, 0, 0, image.width, image.height).also { padded.recycle() }
        val rotation = image.imageInfo.rotationDegrees
        if (rotation == 0) return cropped
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        val rotated = Bitmap.createBitmap(cropped, 0, 0, cropped.width, cropped.height, matrix, true)
        if (rotated !== cropped) cropped.recycle()
        return rotated
    }

    override fun onPause() { videoPlaying = false; selectionFrozen = false; super.onPause() }
    override fun onDestroy() {
        handler.removeCallbacks(videoTick); cameraProvider?.unbindAll(); releaseVideo(); exec.shutdown(); super.onDestroy()
    }
}
