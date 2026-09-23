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
import android.view.View
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
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : AppCompatActivity() {
    private val exec = Executors.newSingleThreadExecutor()
    private val tracker = NccTracker()
    private val busy = AtomicBoolean(false)

    private lateinit var preview: PreviewView
    private lateinit var videoView: ImageView
    private lateinit var overlay: OverlayView
    private lateinit var status: TextView
    private lateinit var sourceLabel: TextView

    private var cameraProvider: ProcessCameraProvider? = null
    private var pendingLock: RectF? = null
    private var locked = false
    private var source = "NONE"
    private var retriever: MediaMetadataRetriever? = null
    private var videoUs = 0L
    private var durationUs = 0L
    private var videoPlaying = false
    @Volatile private var lastVideoFrame: Bitmap? = null
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
            if (source == "VIDEO" && videoPlaying) {
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
        overlay.onLock = { r ->
            if (source == "VIDEO") {
                videoPlaying = false
                val frame = lastVideoFrame
                if (frame == null) {
                    pendingLock = r
                    locked = true
                    setStatus("LOCK queued — waiting for video frame")
                    requestVideoFrame(videoUs)
                } else {
                    setStatus("LOCK applying to displayed frame...")
                    exec.execute {
                        tracker.init(frame, r)
                        pendingLock = null
                        locked = true
                        lastResult = TrackerResult(TrackState.TRACKING, r, r, 1f, 0f, "manual video lock")
                        runOnUiThread {
                            overlay.result = lastResult
                            overlay.invalidate()
                            status.text = "TRACKING q=1.00 0.0 ms | ${tracker.policy}"
                        }
                    }
                }
            } else {
                pendingLock = r
                locked = true
                setStatus("LOCK queued")
            }
        }
        handler.post(videoTick)
    }

    private fun buildUi() {
        val root = FrameLayout(this).apply { setBackgroundColor(0xff07111b.toInt()) }
        preview = PreviewView(this).apply { scaleType = PreviewView.ScaleType.FIT_CENTER }
        videoView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            visibility = View.GONE
        }
        overlay = OverlayView(this)
        root.addView(preview, FrameLayout.LayoutParams(-1, -1))
        root.addView(videoView, FrameLayout.LayoutParams(-1, -1))
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(16))
            background = GradientDrawable().apply {
                setColor(0xee0b1724.toInt())
                cornerRadii = floatArrayOf(
                    dp(20).toFloat(), dp(20).toFloat(),
                    dp(20).toFloat(), dp(20).toFloat(),
                    0f, 0f, 0f, 0f
                )
            }
        }

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        sourceLabel = TextView(this).apply {
            setTextColor(0xffc7d5e1.toInt())
            text = "SOURCE: NONE"
            textSize = 13f
        }
        status = TextView(this).apply {
            setTextColor(Color.WHITE)
            text = "Выберите CAMERA или VIDEO"
            textSize = 14f
            setPadding(0, dp(4), 0, dp(6))
        }
        top.addView(sourceLabel, LinearLayout.LayoutParams(0, -2, 1f))
        top.addView(button("HELP") { showHelp() }, LinearLayout.LayoutParams(dp(72), dp(44)))
        panel.addView(top)
        panel.addView(status)

        val row1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row1.addView(button("CAMERA") { ensureCamera() }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row1.addView(button("VIDEO") { openVideo.launch(arrayOf("video/*")) }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row1.addView(button("RESET") { resetTracker() }, LinearLayout.LayoutParams(0, dp(52), 1f))
        panel.addView(row1)

        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row2.addView(button("QUICK LOCK") {
            if (source == "VIDEO") videoPlaying = false
            overlay.armQuick()
            setStatus(if (source == "VIDEO") "VIDEO PAUSE — тапните по цели" else "Тапните по цели")
        }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row2.addView(button("PRECISE LOCK") {
            if (source == "VIDEO") videoPlaying = false
            overlay.armPrecise()
            setStatus(if (source == "VIDEO") "VIDEO PAUSE — нарисуйте рамку цели" else "Нарисуйте рамку цели")
        }, LinearLayout.LayoutParams(0, dp(52), 1f))
        row2.addView(button("PLAY/PAUSE") {
            if (source == "VIDEO") {
                videoPlaying = !videoPlaying
                setStatus(if (videoPlaying) "VIDEO PLAY" else "VIDEO PAUSE")
            }
        }, LinearLayout.LayoutParams(0, dp(52), 1f))
        panel.addView(row2)

        root.addView(panel, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(root)
    }

    private fun button(title: String, action: () -> Unit) = Button(this).apply {
        text = title
        setAllCaps(false)
        setTextColor(Color.WHITE)
        textSize = 12f
        gravity = Gravity.CENTER
        minHeight = dp(44)
        elevation = 0f
        stateListAnimator = null
        background = GradientDrawable().apply {
            setColor(0xff162536.toInt())
            cornerRadius = dp(14).toFloat()
        }
        setOnClickListener { action() }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun setStatus(message: String) {
        runOnUiThread { status.text = message }
    }

    private fun showHelp() {
        AlertDialog.Builder(this)
            .setTitle("Real-0 Tracker Lab")
            .setMessage(
                """
                CAMERA — живая камера телефона.
                VIDEO — локальный видеофайл.
                QUICK LOCK — нажмите кнопку и затем один раз тапните по цели.
                PRECISE LOCK — нажмите кнопку и один раз нарисуйте рамку вокруг цели.
                RESET — удалить текущий захват и отменить ожидающий LOCK.

                TRACKING — уверенное сопровождение.
                UNCERTAIN — уверенность снижена.
                LOST — измеренная рамка скрывается.
                Голубой пунктир — только прогноз, не подтверждённое измерение.

                GT не используется в рабочем tracking pipeline. Стенд работает локально и не имеет flight-control выходов.
                """.trimIndent()
            )
            .setPositiveButton("OK", null)
            .show()
    }

    private fun ensureCamera() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            cameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    private fun startCamera() {
        releaseVideo()
        source = "CAMERA"
        sourceLabel.text = "SOURCE: CAMERA"
        videoView.visibility = View.GONE
        preview.visibility = View.VISIBLE
        resetTracker()
        setStatus("Запуск камеры...")

        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            runCatching {
                val provider = future.get()
                cameraProvider = provider
                if (source != "CAMERA") {
                    provider.unbindAll()
                    return@runCatching
                }
                val cameraPreview = Preview.Builder().build().also {
                    it.setSurfaceProvider(preview.surfaceProvider)
                }
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                analysis.setAnalyzer(exec) { image -> analyzeCamera(image) }
                provider.unbindAll()
                provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, cameraPreview, analysis)
                setStatus("Камера готова. Выберите QUICK/PRECISE LOCK")
            }.onFailure {
                setStatus("CAMERA ERROR: ${it.message}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun analyzeCamera(image: ImageProxy) {
        if (source != "CAMERA") {
            image.close()
            return
        }
        try {
            processFrame(toBitmap(image))
        } finally {
            image.close()
        }
    }

    private fun loadVideo(uri: Uri) {
        cameraProvider?.unbindAll()
        runCatching {
            val r = MediaMetadataRetriever()
            r.setDataSource(this, uri)
            retriever?.release()
            retriever = r
            durationUs = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000L
            videoUs = 0L
            source = "VIDEO"
            sourceLabel.text = "SOURCE: VIDEO"
            preview.visibility = View.GONE
            videoView.visibility = View.VISIBLE
            videoPlaying = false
            resetTracker()
            requestVideoFrame(0L)
            setStatus("Видео загружено. LOCK, затем PLAY")
        }.onFailure {
            setStatus("VIDEO ERROR: ${it.message}")
        }
    }

    private fun requestVideoFrame(us: Long) {
        if (!busy.compareAndSet(false, true)) return
        exec.execute {
            try {
                val r = retriever
                if (source == "VIDEO" && r != null) {
                    val bm = runCatching {
                        r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST)
                    }.getOrElse {
                        if (source == "VIDEO") setStatus("VIDEO FRAME ERROR: ${it.message}")
                        null
                    }
                    if (bm != null && source == "VIDEO") {
                        lastVideoFrame = bm
                        runOnUiThread { videoView.setImageBitmap(bm) }
                        processFrame(bm)
                    }
                }
            } finally {
                busy.set(false)
            }
        }
    }

    private fun processFrame(bitmap: Bitmap) {
        overlay.frameW = bitmap.width
        overlay.frameH = bitmap.height
        var justLocked = false
        pendingLock?.let {
            tracker.init(bitmap, it)
            pendingLock = null
            lastResult = TrackerResult(TrackState.TRACKING, it, it, 1f, 0f, "manual lock")
            justLocked = true
        }
        if (locked && pendingLock == null && !justLocked) {
            lastResult = tracker.update(bitmap)
        }
        runOnUiThread {
            overlay.result = lastResult
            overlay.invalidate()
            status.text = "${lastResult.state} q=${"%.2f".format(lastResult.quality)} ${"%.1f".format(lastResult.processingMs)} ms | ${tracker.policy}"
        }
    }

    private fun resetTracker() {
        locked = false
        pendingLock = null
        overlay.disarm()
        tracker.reset()
        lastResult = TrackerResult(
            if (source == "NONE") TrackState.IDLE else TrackState.READY,
            null,
            null,
            0f,
            0f,
            "reset"
        )
        overlay.result = lastResult
        overlay.invalidate()
        setStatus(if (source == "NONE") "Выберите CAMERA или VIDEO" else "Готово. Выберите QUICK/PRECISE LOCK")
    }

    private fun releaseVideo() {
        videoPlaying = false
        lastVideoFrame = null
        retriever?.release()
        retriever = null
        videoUs = 0L
        durationUs = 0L
    }

    private fun toBitmap(image: ImageProxy): Bitmap {
        val bitmap = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        image.planes[0].buffer.rewind()
        bitmap.copyPixelsFromBuffer(image.planes[0].buffer)
        val rotation = image.imageInfo.rotationDegrees
        if (rotation == 0) return bitmap
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    override fun onPause() {
        videoPlaying = false
        super.onPause()
    }

    override fun onDestroy() {
        handler.removeCallbacks(videoTick)
        cameraProvider?.unbindAll()
        releaseVideo()
        exec.shutdown()
        super.onDestroy()
    }
}
